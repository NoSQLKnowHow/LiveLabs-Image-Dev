"""
============================================================================
PRISM: Vector Ingestion Pipeline
============================================================================
Reads maintenance log narratives, inspection report summaries, and
inspection finding descriptions, chunks them using
DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS, generates embeddings using the ONNX
DEMO_MODEL, and stores the results in the DOCUMENT_CHUNKS table.

Usage:
    python prism-ingest.py

Run after: prism-seed.py
Run before: prism-indexes.sql

Requires:
    - python-oracledb
    - DEMO_MODEL loaded in the database (see load-prism-database-free.md)
    - Environment variables (see .env)
============================================================================
"""

import json
import os
import sys
import time

from dotenv import load_dotenv
load_dotenv()

import oracledb

# Tell python-oracledb to return LOB columns as Python strings/bytes
# instead of LOB objects. Without this, CLOB columns (like narrative)
# return objects that don't support string methods like .strip().
oracledb.defaults.fetch_lobs = False

# ============================================================================
# Configuration
# ============================================================================

ORACLE_DSN = os.environ.get("DBCONNECTION", "aidbfree:1521/freepdb1")
ORACLE_USER = os.environ.get("ORACLE_USER", "prism")
ORACLE_PASSWORD = os.environ.get("DBPASSWORD", "WelcometoOracle26ai")
ORACLE_WALLET_DIR = os.environ.get("ORACLE_WALLET_DIR")

# Chunking configuration
# These can be tuned based on the content characteristics.
CHUNK_MAX_SIZE = 1000       # maximum chunk size in characters
CHUNK_OVERLAP = 100         # overlap between chunks in characters
CHUNK_SPLIT_BY = "sentence" # split strategy: sentence, word, character

# Embedding model name (must match what was loaded in load-prism-database-free.md)
EMBEDDING_MODEL = "DEMO_MODEL"

# Batch size for database operations
BATCH_SIZE = 50


# ============================================================================
# Database Connection
# ============================================================================

def get_connection():
    """Create and return an Oracle database connection."""
    wallet_dir = ORACLE_WALLET_DIR.strip() if ORACLE_WALLET_DIR else ""
    if wallet_dir and os.path.isdir(wallet_dir):
        print(f"  Using wallet connection (wallet dir: {wallet_dir})")
        return oracledb.connect(
            user=ORACLE_USER,
            password=ORACLE_PASSWORD,
            dsn=ORACLE_DSN,
            config_dir=wallet_dir,
            wallet_location=wallet_dir,
            wallet_password=ORACLE_PASSWORD
        )
    else:
        print(f"  Using direct connection (DSN: {ORACLE_DSN})")
        return oracledb.connect(
            user=ORACLE_USER,
            password=ORACLE_PASSWORD,
            dsn=ORACLE_DSN
        )


# ============================================================================
# Ingestion Pipeline
# ============================================================================

# Build the UTL_TO_CHUNKS config JSON once (used in every chunk_and_embed call).
CHUNK_PARAMS = json.dumps({
    "max": CHUNK_MAX_SIZE,
    "overlap": CHUNK_OVERLAP,
    "split": CHUNK_SPLIT_BY,
    "normalize": "all"
})


def chunk_and_embed(cursor, source_table, source_id, text):
    """
    Chunk a piece of text using DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS, embed
    each chunk using DEMO_MODEL, and insert the results into DOCUMENT_CHUNKS.

    Uses UTL_TO_CHUNKS (PL/SQL package) instead of VECTOR_CHUNKS (SQL function)
    because UTL_TO_CHUNKS accepts JSON parameters via bind variables and works
    reliably across Oracle Free Docker and ADB environments.

    Returns the number of chunks created.
    """
    # Handle LOB objects and empty text
    if hasattr(text, 'read'):
        text = text.read()
    if not text or not str(text).strip():
        return 0
    text = str(text)

    # Step 1: Chunk the text using DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS
    # Returns a VECTOR_ARRAY_T; each element is a JSON object with
    # chunk_id, chunk_offset, chunk_length, and chunk_data fields.
    cursor.execute("""
        SELECT et.column_value
        FROM TABLE(
            DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS(
                :input_text,
                JSON(:chunk_params)
            )
        ) et
    """, {
        "input_text": text,
        "chunk_params": CHUNK_PARAMS,
    })
    chunks = cursor.fetchall()

    if not chunks:
        return 0

    # Step 2 & 3: Embed each chunk and insert into DOCUMENT_CHUNKS
    # Note: VECTOR_EMBEDDING expects the model name as a SQL identifier,
    # not a bind variable, so it is interpolated into the SQL string.
    chunk_count = 0
    for idx, (chunk_value,) in enumerate(chunks, start=1):
        # UTL_TO_CHUNKS returns JSON objects; extract the chunk text.
        # The JSON structure has a "chunk_data" field with the text.
        if isinstance(chunk_value, str):
            try:
                chunk_data = json.loads(chunk_value)
                chunk_text = chunk_data.get("chunk_data", chunk_value)
            except json.JSONDecodeError:
                chunk_text = chunk_value
        elif isinstance(chunk_value, dict):
            chunk_text = chunk_value.get("chunk_data", str(chunk_value))
        else:
            chunk_text = str(chunk_value)

        if not chunk_text or not chunk_text.strip():
            continue

        cursor.execute(f"""
            INSERT INTO document_chunks (source_table, source_id, chunk_seq, chunk_text, embedding)
            VALUES (
                :source_table,
                :source_id,
                :chunk_seq,
                :chunk_text,
                VECTOR_EMBEDDING({EMBEDDING_MODEL} USING :chunk_text AS data)
            )
        """, {
            "source_table": source_table,
            "source_id": source_id,
            "chunk_seq": idx,
            "chunk_text": chunk_text,
        })
        chunk_count += 1

    return chunk_count


def ingest_maintenance_logs(conn, cursor):
    """Process all maintenance logs through the chunking and embedding pipeline."""
    print("\n--- Ingesting Maintenance Logs ---")

    cursor.execute("""
        SELECT log_id, narrative
        FROM maintenance_logs
        WHERE log_id NOT IN (
            SELECT DISTINCT source_id FROM document_chunks WHERE source_table = 'maintenance_logs'
        )
        ORDER BY log_id
    """)
    logs = cursor.fetchall()
    print(f"  Found {len(logs)} logs to process.")

    total_chunks = 0
    processed = 0

    for log_id, narrative in logs:
        try:
            chunks_created = chunk_and_embed(cursor, "maintenance_logs", log_id, narrative)
            total_chunks += chunks_created
            processed += 1

            if processed % BATCH_SIZE == 0:
                conn.commit()
                print(f"  Processed {processed}/{len(logs)} logs ({total_chunks} chunks so far)...")

        except Exception as e:
            print(f"  ERROR processing log_id {log_id}: {e}")
            conn.rollback()
            continue

    conn.commit()
    print(f"  Completed: {processed} logs, {total_chunks} chunks created.")
    return total_chunks


def ingest_inspection_reports(conn, cursor):
    """Process all inspection report summaries through the pipeline."""
    print("\n--- Ingesting Inspection Report Summaries ---")

    cursor.execute("""
        SELECT report_id, summary
        FROM inspection_reports
        WHERE summary IS NOT NULL
        AND report_id NOT IN (
            SELECT DISTINCT source_id FROM document_chunks WHERE source_table = 'inspection_reports'
        )
        ORDER BY report_id
    """)
    reports = cursor.fetchall()
    print(f"  Found {len(reports)} report summaries to process.")

    total_chunks = 0
    processed = 0

    for report_id, summary in reports:
        try:
            chunks_created = chunk_and_embed(cursor, "inspection_reports", report_id, summary)
            total_chunks += chunks_created
            processed += 1

            if processed % BATCH_SIZE == 0:
                conn.commit()
                print(f"  Processed {processed}/{len(reports)} reports ({total_chunks} chunks so far)...")

        except Exception as e:
            print(f"  ERROR processing report_id {report_id}: {e}")
            conn.rollback()
            continue

    conn.commit()
    print(f"  Completed: {processed} reports, {total_chunks} chunks created.")
    return total_chunks


def ingest_inspection_findings(conn, cursor):
    """Process all inspection finding descriptions through the pipeline."""
    print("\n--- Ingesting Inspection Finding Descriptions ---")

    cursor.execute("""
        SELECT finding_id, description
        FROM inspection_findings
        WHERE description IS NOT NULL
        AND finding_id NOT IN (
            SELECT DISTINCT source_id FROM document_chunks WHERE source_table = 'inspection_findings'
        )
        ORDER BY finding_id
    """)
    findings = cursor.fetchall()
    print(f"  Found {len(findings)} finding descriptions to process.")

    total_chunks = 0
    processed = 0

    for finding_id, description in findings:
        try:
            chunks_created = chunk_and_embed(cursor, "inspection_findings", finding_id, description)
            total_chunks += chunks_created
            processed += 1

            if processed % BATCH_SIZE == 0:
                conn.commit()
                print(f"  Processed {processed}/{len(findings)} findings ({total_chunks} chunks so far)...")

        except Exception as e:
            print(f"  ERROR processing finding_id {finding_id}: {e}")
            conn.rollback()
            continue

    conn.commit()
    print(f"  Completed: {processed} findings, {total_chunks} chunks created.")
    return total_chunks


# ============================================================================
# Main
# ============================================================================

def main():
    print("=" * 72)
    print("  PRISM: Vector Ingestion Pipeline")
    print("=" * 72)

    # Validate configuration
    if not ORACLE_DSN or not ORACLE_PASSWORD:
        print("ERROR: ORACLE_DSN and ORACLE_PASSWORD environment variables are required.")
        sys.exit(1)

    # Connect
    print("\nConnecting to Oracle database...")
    conn = get_connection()
    cursor = conn.cursor()
    print("  Connected.")

    # Verify DEMO_MODEL is loaded
    print("\nVerifying embedding model...")
    cursor.execute("""
        SELECT owner, model_name FROM all_mining_models WHERE model_name = :model_name;
    """, {"model_name": EMBEDDING_MODEL})
    model = cursor.fetchone()
    if not model:
        print(f"  ERROR: Embedding model '{EMBEDDING_MODEL}' not found.")
        print("  Load the ONNX model first (see load-prism-database-free.md).")
        cursor.close()
        conn.close()
        sys.exit(1)
    print(f"  Model '{EMBEDDING_MODEL}' found.")

    # Check source data availability
    print("\nSource data counts:")
    for table in ["maintenance_logs", "inspection_reports", "inspection_findings"]:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        count = cursor.fetchone()[0]
        print(f"  {table:30s} {count:>6d} rows")

    cursor.execute("SELECT COUNT(*) FROM maintenance_logs")
    if cursor.fetchone()[0] == 0:
        print("\nERROR: No source data found. Run prism-seed.py first.")
        cursor.close()
        conn.close()
        sys.exit(1)

    # Run ingestion
    start_time = time.time()

    log_chunks = ingest_maintenance_logs(conn, cursor)
    report_chunks = ingest_inspection_reports(conn, cursor)
    finding_chunks = ingest_inspection_findings(conn, cursor)

    elapsed = time.time() - start_time

    # Final summary
    print("\n--- Ingestion Summary ---")
    cursor.execute("SELECT source_table, COUNT(*) FROM document_chunks GROUP BY source_table ORDER BY source_table")
    for row in cursor.fetchall():
        print(f"  {row[0]:30s} {row[1]:>6d} chunks")

    cursor.execute("SELECT COUNT(*) FROM document_chunks")
    total = cursor.fetchone()[0]
    print(f"  {'TOTAL':30s} {total:>6d} chunks")
    print(f"\n  Elapsed time: {elapsed:.1f} seconds")

    cursor.close()
    conn.close()

    print()
    print("=" * 72)
    print("  Vector ingestion complete.")
    print("  Next step: Run prism-indexes.sql to create the HNSW vector index.")
    print("=" * 72)


if __name__ == "__main__":
    main()
