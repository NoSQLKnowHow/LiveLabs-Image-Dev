#!/bin/bash
set -euo pipefail

APP_USER="$(echo "prism" | tr '[:lower:]' '[:upper:]')"
export DBPASSWORD="${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-Welcome202626ai}}"
export DBUSER="$(echo "prism" | tr '[:lower:]' '[:upper:]')"
export DBCONNECTION="${DBCONNECTION:-localhost:1521/freepdb1}"

sqlplus ${DBUSER}/${DBPASSWORD}@${DBCONNECTION} <<SQL
whenever sqlerror exit sql.sqlcode;
SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = ${APP_USER};

PROMPT
PROMPT [3/12] Creating startup build log...

CREATE TABLE prism_build_log (
    log_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    step_name  VARCHAR2(100) NOT NULL,
    status     VARCHAR2(20)  NOT NULL,
    detail     VARCHAR2(4000),
    started_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    ended_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);

PROMPT         Table PRISM_BUILD_LOG created.

PROMPT
PROMPT [4/12] Creating canonical tables (DISTRICTS, INFRASTRUCTURE_ASSETS)...

CREATE TABLE districts (
    district_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name             VARCHAR2(100) NOT NULL,
    classification   VARCHAR2(50)  NOT NULL,
    population       NUMBER,
    area_sq_km       NUMBER(10,2),
    center_latitude  NUMBER(9,6),
    center_longitude NUMBER(9,6),
    boundary         SDO_GEOMETRY,
    description      VARCHAR2(4000)
);

PROMPT         Table DISTRICTS created.

CREATE TABLE infrastructure_assets (
    asset_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    district_id       NUMBER NOT NULL REFERENCES districts(district_id),
    name              VARCHAR2(200) NOT NULL,
    asset_type        VARCHAR2(100) NOT NULL,
    status            VARCHAR2(50)  DEFAULT 'active',
    criticality       NUMBER(1) DEFAULT 3 NOT NULL,
    latitude          NUMBER(9,6),
    longitude         NUMBER(9,6),
    location          SDO_GEOMETRY,
    commissioned_date DATE,
    description       VARCHAR2(4000),
    specifications    JSON,
    CONSTRAINT chk_assets_criticality CHECK (criticality BETWEEN 1 AND 5)
);

PROMPT         Table INFRASTRUCTURE_ASSETS created.

-- ----------------------------------------------------------------------------
-- 5. Create JSON collection table
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [5/12] Creating JSON collection table (OPERATIONAL_PROCEDURES)...

CREATE JSON COLLECTION TABLE operational_procedures;

PROMPT         Table OPERATIONAL_PROCEDURES created.

-- ----------------------------------------------------------------------------
-- 6. Create remaining canonical tables
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [6/12] Creating remaining tables...

CREATE TABLE maintenance_logs (
    log_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id     NUMBER NOT NULL REFERENCES infrastructure_assets(asset_id),
    log_date     DATE DEFAULT SYSDATE,
    severity     VARCHAR2(20),
    narrative    VARCHAR2(4000) NOT NULL
);

PROMPT         Table MAINTENANCE_LOGS created.

CREATE TABLE inspection_reports (
    report_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id      NUMBER NOT NULL REFERENCES infrastructure_assets(asset_id),
    inspector     VARCHAR2(200),
    inspect_date  DATE DEFAULT SYSDATE,
    overall_grade VARCHAR2(10),
    summary       VARCHAR2(4000)
);

PROMPT         Table INSPECTION_REPORTS created.

CREATE TABLE inspection_findings (
    finding_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id      NUMBER NOT NULL REFERENCES inspection_reports(report_id),
    category       VARCHAR2(100),
    severity       VARCHAR2(20),
    description    VARCHAR2(4000),
    recommendation VARCHAR2(4000)
);

PROMPT         Table INSPECTION_FINDINGS created.

CREATE TABLE asset_connections (
    connection_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_asset_id   NUMBER NOT NULL REFERENCES infrastructure_assets(asset_id),
    to_asset_id     NUMBER NOT NULL REFERENCES infrastructure_assets(asset_id),
    connection_type VARCHAR2(100),
    description     VARCHAR2(4000)
);

PROMPT         Table ASSET_CONNECTIONS created.

CREATE TABLE document_chunks (
    chunk_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_table   VARCHAR2(50)  NOT NULL,
    source_id      NUMBER,
    source_key     VARCHAR2(200),
    source_label   VARCHAR2(200),
    source_date    DATE,
    chunk_seq      NUMBER        NOT NULL,
    chunk_text     VARCHAR2(4000) NOT NULL,
    model_name     VARCHAR2(128) NOT NULL,
    chunk_params   JSON,
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    embedding      VECTOR        NOT NULL
);

PROMPT         Table DOCUMENT_CHUNKS created.

-- ----------------------------------------------------------------------------
-- 7. Create standard indexes
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [7/12] Creating standard indexes...

-- Infrastructure assets
CREATE INDEX idx_assets_district ON infrastructure_assets(district_id);
CREATE INDEX idx_assets_type ON infrastructure_assets(asset_type);
CREATE INDEX idx_assets_status ON infrastructure_assets(status);
CREATE INDEX idx_assets_criticality ON infrastructure_assets(criticality);

PROMPT         Indexes on INFRASTRUCTURE_ASSETS created.

-- Maintenance logs
CREATE INDEX idx_maint_logs_asset ON maintenance_logs(asset_id);
CREATE INDEX idx_maint_logs_date ON maintenance_logs(log_date);
CREATE INDEX idx_maint_logs_severity ON maintenance_logs(severity);

PROMPT         Indexes on MAINTENANCE_LOGS created.

-- Inspection reports
CREATE INDEX idx_insp_reports_asset ON inspection_reports(asset_id);
CREATE INDEX idx_insp_reports_date ON inspection_reports(inspect_date);

PROMPT         Indexes on INSPECTION_REPORTS created.

-- Inspection findings
CREATE INDEX idx_insp_findings_report ON inspection_findings(report_id);
CREATE INDEX idx_insp_findings_severity ON inspection_findings(severity);

PROMPT         Indexes on INSPECTION_FINDINGS created.

-- Asset connections
CREATE INDEX idx_asset_conn_from ON asset_connections(from_asset_id);
CREATE INDEX idx_asset_conn_to ON asset_connections(to_asset_id);
CREATE INDEX idx_asset_conn_type ON asset_connections(connection_type);

PROMPT         Indexes on ASSET_CONNECTIONS created.

-- Document chunks (for lookups by source)
CREATE INDEX idx_doc_chunks_source ON document_chunks(source_table, source_id);
CREATE INDEX idx_doc_chunks_source_key ON document_chunks(source_table, source_key);

PROMPT         Indexes on DOCUMENT_CHUNKS created.

PROMPT
PROMPT [8/12] Creating spatial metadata and indexes...

INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES (
    'DISTRICTS',
    'BOUNDARY',
    SDO_DIM_ARRAY(
        SDO_DIM_ELEMENT('LONGITUDE', -79.900000, -79.800000, 0.000005),
        SDO_DIM_ELEMENT('LATITUDE',   38.880000,  38.970000, 0.000005)
    ),
    4326
);

INSERT INTO user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
VALUES (
    'INFRASTRUCTURE_ASSETS',
    'LOCATION',
    SDO_DIM_ARRAY(
        SDO_DIM_ELEMENT('LONGITUDE', -79.900000, -79.800000, 0.000005),
        SDO_DIM_ELEMENT('LATITUDE',   38.880000,  38.970000, 0.000005)
    ),
    4326
);

CREATE INDEX idx_districts_boundary
    ON districts(boundary)
    INDEXTYPE IS MDSYS.SPATIAL_INDEX;

CREATE INDEX idx_assets_location
    ON infrastructure_assets(location)
    INDEXTYPE IS MDSYS.SPATIAL_INDEX;

PROMPT         Spatial indexes created.

-- ----------------------------------------------------------------------------
-- 9. Create JSON Duality View
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [9/12] Creating JSON Duality View (INSPECTION_REPORT_DV)...

CREATE JSON RELATIONAL DUALITY VIEW inspection_report_dv AS
    inspection_reports @insert @update @delete {
        _id        : report_id,
        asset_id   : asset_id,
        inspector  : inspector,
        inspectDate: inspect_date,
        grade      : overall_grade,
        summary    : summary,
        findings   : inspection_findings @insert @update @delete {
            findingId      : finding_id,
            category       : category,
            severity       : severity,
            description    : description,
            recommendation : recommendation
        }
    };

PROMPT         Duality View INSPECTION_REPORT_DV created.

-- ----------------------------------------------------------------------------
-- 10. Create SQL/PGQ property graph
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [10/12] Creating SQL/PGQ property graph (CITYPULSE_GRAPH)...

CREATE PROPERTY GRAPH citypulse_graph
    VERTEX TABLES (
        infrastructure_assets
            KEY (asset_id)
            LABEL asset
            PROPERTIES (name, asset_type, status, criticality, district_id, latitude, longitude)
    )
    EDGE TABLES (
        asset_connections
            KEY (connection_id)
            SOURCE KEY (from_asset_id) REFERENCES infrastructure_assets (asset_id)
            DESTINATION KEY (to_asset_id) REFERENCES infrastructure_assets (asset_id)
            LABEL connected_to
            PROPERTIES (connection_type, description)
    );

PROMPT         Property graph CITYPULSE_GRAPH created.

-- ----------------------------------------------------------------------------
-- 11. Create vector chunk views
-- ----------------------------------------------------------------------------
-- These views make the learner/API query surface simpler. V_ASSET_SPECS_SUMMARY
-- exposes common JSON specification fields as relational columns, and the chunk
-- views pre-join DOCUMENT_CHUNKS with their source tables.
-- Note: Chunk views are created now but return no rows until the SQL seed loader
-- and vector ingestion pipeline have run.
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [11/12] Creating helper views...

CREATE OR REPLACE VIEW v_asset_specs_summary AS
    SELECT a.asset_id,
           a.name AS asset_name,
           a.asset_type,
           a.status,
           a.criticality,
           a.latitude,
           a.longitude,
           to_char(a.latitude, 'FM990.000000') || ', ' || to_char(a.longitude, 'FM990.000000') AS google_maps_lat_lon,
           a.location,
           d.name AS district_name,
           a.specifications.spanLength_m.number()       AS span_length_m,
           a.specifications.loadCapacity_t.number()     AS load_capacity_t,
           a.specifications.voltageRating_kv.number()   AS voltage_rating_kv,
           a.specifications.transformerCount.number()   AS transformer_count,
           a.specifications.peakCapacity_mw.number()    AS peak_capacity_mw,
           a.specifications.diameter_mm.number()        AS diameter_mm,
           a.specifications.pressureRating_kpa.number() AS pressure_rating_kpa,
           a.specifications.length_km.number()          AS length_km,
           a.specifications.height_m.number()           AS height_m,
           a.specifications.backupPowerHours.number()   AS backup_power_hours,
           a.specifications.operatingSeats.number()     AS operating_seats,
           a.specifications.incidentRooms.number()      AS incident_rooms,
           a.specifications.dispatchConsoles.number()   AS dispatch_consoles,
           a.specifications.material.string()           AS material,
           a.specifications.coolingType.string()        AS cooling_type,
           a.specifications.backhaul.string()           AS backhaul,
           a.specifications.backupPower.string()        AS backup_power,
           a.specifications.activationTrigger.string()  AS activation_trigger,
           a.specifications
    FROM infrastructure_assets a
    JOIN districts d ON a.district_id = d.district_id;

PROMPT         View V_ASSET_SPECS_SUMMARY created.

CREATE OR REPLACE VIEW v_operational_procedure_summary AS
    SELECT json_value(data, '$.procedureId' RETURNING VARCHAR2(50)) AS procedure_id,
           json_value(data, '$.title' RETURNING VARCHAR2(200)) AS title,
           json_value(data, '$.category' RETURNING VARCHAR2(100)) AS category,
           json_value(data, '$.version' RETURNING VARCHAR2(50)) AS version,
           json_value(data, '$.lastRevised' RETURNING VARCHAR2(30)) AS last_revised,
           json_value(data, '$.estimatedDuration_min' RETURNING NUMBER) AS estimated_duration_min,
           json_value(data, '$.requiredPersonnel' RETURNING NUMBER) AS required_personnel,
           json_value(data, '$.escalation.contact' RETURNING VARCHAR2(200)) AS escalation_contact,
           json_value(data, '$.escalation.phone' RETURNING VARCHAR2(50)) AS escalation_phone,
           data AS procedure_json
    FROM operational_procedures;

PROMPT         View V_OPERATIONAL_PROCEDURE_SUMMARY created.

CREATE OR REPLACE VIEW v_operational_procedure_documents AS
    SELECT json_value(data, '$.procedureId' RETURNING VARCHAR2(50)) AS procedure_id,
           data AS procedure_document
    FROM operational_procedures;

PROMPT         View V_OPERATIONAL_PROCEDURE_DOCUMENTS created.

PROMPT
PROMPT         Creating vector chunk views...

-- Individual source view: maintenance log chunks
CREATE OR REPLACE VIEW v_chunks_maintenance_logs AS
    SELECT dc.chunk_id, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           ml.asset_id, ml.severity, ml.log_date,
           a.name AS asset_name, a.asset_type, a.criticality, a.latitude, a.longitude,
           d.district_id, d.name AS district_name
    FROM document_chunks dc
    JOIN maintenance_logs ml ON dc.source_id = ml.log_id
    JOIN infrastructure_assets a ON ml.asset_id = a.asset_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE dc.source_table = 'maintenance_logs';

PROMPT         View V_CHUNKS_MAINTENANCE_LOGS created.

-- Individual source view: inspection report summary chunks
CREATE OR REPLACE VIEW v_chunks_inspection_reports AS
    SELECT dc.chunk_id, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           ir.asset_id, ir.overall_grade, ir.inspect_date, ir.inspector,
           a.name AS asset_name, a.asset_type, a.criticality, a.latitude, a.longitude,
           d.district_id, d.name AS district_name
    FROM document_chunks dc
    JOIN inspection_reports ir ON dc.source_id = ir.report_id
    JOIN infrastructure_assets a ON ir.asset_id = a.asset_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE dc.source_table = 'inspection_reports';

PROMPT    View V_CHUNKS_INSPECTION_REPORTS created.

-- Individual source view: inspection finding chunks
CREATE OR REPLACE VIEW v_chunks_inspection_findings AS
    SELECT dc.chunk_id, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           inf.report_id, inf.category, inf.severity,
           ir.asset_id, ir.inspect_date,
           a.name AS asset_name, a.asset_type, a.criticality, a.latitude, a.longitude,
           d.district_id, d.name AS district_name
    FROM document_chunks dc
    JOIN inspection_findings inf ON dc.source_id = inf.finding_id
    JOIN inspection_reports ir ON inf.report_id = ir.report_id
    JOIN infrastructure_assets a ON ir.asset_id = a.asset_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE dc.source_table = 'inspection_findings';

PROMPT   View V_CHUNKS_INSPECTION_FINDINGS created.

-- Individual source view: operational procedure chunks.
CREATE OR REPLACE VIEW v_chunks_operational_procedures AS
    SELECT dc.chunk_id, dc.source_key AS procedure_id, dc.source_label AS procedure_title,
           dc.chunk_seq, dc.chunk_text, dc.model_name, dc.chunk_params,
           dc.created_at, dc.embedding
    FROM document_chunks dc
    WHERE dc.source_table = 'operational_procedures';

PROMPT   View V_CHUNKS_OPERATIONAL_PROCEDURES created.

-- Unified view: all chunks joined to source data with common columns.
-- This is the primary view for cross-source vector search in the API.
CREATE OR REPLACE VIEW v_chunks_unified AS
    SELECT dc.chunk_id, dc.source_table, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           ml.severity,
           a.asset_id, a.name AS asset_name, a.asset_type, a.criticality, a.latitude, a.longitude,
           d.district_id, d.name AS district_name
    FROM document_chunks dc
    JOIN maintenance_logs ml ON dc.source_id = ml.log_id
    JOIN infrastructure_assets a ON ml.asset_id = a.asset_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE dc.source_table = 'maintenance_logs'
    UNION ALL
    SELECT dc.chunk_id, dc.source_table, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           ir.overall_grade AS severity,
           a.asset_id, a.name AS asset_name, a.asset_type, a.criticality, a.latitude, a.longitude,
           d.district_id, d.name AS district_name
    FROM document_chunks dc
    JOIN inspection_reports ir ON dc.source_id = ir.report_id
    JOIN infrastructure_assets a ON ir.asset_id = a.asset_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE dc.source_table = 'inspection_reports'
    UNION ALL
    SELECT dc.chunk_id, dc.source_table, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           inf.severity,
           a.asset_id, a.name AS asset_name, a.asset_type, a.criticality, a.latitude, a.longitude,
           d.district_id, d.name AS district_name
    FROM document_chunks dc
    JOIN inspection_findings inf ON dc.source_id = inf.finding_id
    JOIN inspection_reports ir ON inf.report_id = ir.report_id
    JOIN infrastructure_assets a ON ir.asset_id = a.asset_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE dc.source_table = 'inspection_findings'
    UNION ALL
    SELECT dc.chunk_id, dc.source_table, dc.source_id, dc.source_key, dc.source_label,
           dc.source_date, dc.chunk_seq, dc.chunk_text, dc.model_name,
           dc.chunk_params, dc.created_at, dc.embedding,
           CAST(NULL AS VARCHAR2(20)) AS severity,
           CAST(NULL AS NUMBER) AS asset_id, CAST(NULL AS VARCHAR2(200)) AS asset_name,
           CAST(NULL AS VARCHAR2(100)) AS asset_type, CAST(NULL AS NUMBER) AS criticality,
           CAST(NULL AS NUMBER) AS latitude, CAST(NULL AS NUMBER) AS longitude,
           CAST(NULL AS NUMBER) AS district_id, CAST(NULL AS VARCHAR2(100)) AS district_name
    FROM document_chunks dc
    WHERE dc.source_table = 'operational_procedures';

PROMPT  View V_CHUNKS_UNIFIED created.

CREATE OR REPLACE VIEW v_prism_model_map AS
    SELECT 'District' AS concept,
           'Relational + Spatial' AS data_surface,
           'DISTRICTS' AS database_object,
           'Rows hold district attributes; BOUNDARY stores SDO_GEOMETRY polygons.' AS access_pattern,
           'Find assets inside or near an Elkins district.' AS example_topic
    FROM dual
    UNION ALL
    SELECT 'Infrastructure Asset', 'Relational + JSON + Spatial + Graph',
           'INFRASTRUCTURE_ASSETS',
           'Rows hold canonical asset facts, SPECIFICATIONS stores flexible JSON, LOCATION stores SDO_GEOMETRY, and CITYPULSE_GRAPH exposes assets as vertices.',
           'Compare critical bridge assets by district, JSON specification, location, and graph dependency.'
    FROM dual
    UNION ALL
    SELECT 'Asset Dependency', 'Relational + Graph',
           'ASSET_CONNECTIONS / CITYPULSE_GRAPH',
           'Foreign keys store asset-to-asset relationships; SQL/PGQ traverses them as graph edges.',
           'Trace what Substation Gamma powers or what the Emergency Operations Center coordinates.'
    FROM dual
    UNION ALL
    SELECT 'Operational Procedure', 'JSON + Vector',
           'OPERATIONAL_PROCEDURES / V_OPERATIONAL_PROCEDURE_DOCUMENTS / V_OPERATIONAL_PROCEDURE_SUMMARY / V_CHUNKS_OPERATIONAL_PROCEDURES',
           'JSON documents preserve SOP structure; document, helper, and chunk views expose them for JSON-native browsing, SQL projection, and semantic search.',
           'Find the SOP that applies to a pipeline leak or substation relay failure.'
    FROM dual
    UNION ALL
    SELECT 'Inspection Report', 'Relational + JSON Duality + Vector',
           'INSPECTION_REPORTS / INSPECTION_FINDINGS / INSPECTION_REPORT_DV / V_CHUNKS_INSPECTION_REPORTS',
           'Normalized rows support joins, the duality view exposes document-shaped reports, and chunks enable semantic search.',
           'Retrieve findings for a poor-grade inspection and ask semantic questions about root cause.'
    FROM dual
    UNION ALL
    SELECT 'Maintenance Narrative', 'Relational + Vector',
           'MAINTENANCE_LOGS / V_CHUNKS_MAINTENANCE_LOGS',
           'Operational logs remain relational while embedded chunks support natural-language retrieval.',
           'Search recent evidence for structural, electrical, or pipeline risk.'
    FROM dual;

PROMPT  View V_PRISM_MODEL_MAP created.

insert into prism_build_log (step_name, status, detail)
values ('30-create-prism-db-objects', 'SUCCESS', 'Schema, indexes, graph, spatial metadata, and helper views created.');

commit;
/

exit;
SQL
