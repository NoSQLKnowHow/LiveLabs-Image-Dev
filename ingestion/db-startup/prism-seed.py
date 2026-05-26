"""
============================================================================
PRISM: Seed Data Loader
============================================================================
Populates the Prism database with CityPulse sample data.

Structural data (districts, assets, connections, procedures) is defined
inline. Narrative content (maintenance logs, inspection reports, findings)
is loaded from pre-generated JSON files in the data/ directory.

To generate the JSON data files, run prism-generate.py first (one time).

Usage:
    python prism-seed.py

Requires:
    - python-oracledb
    - python-dotenv
    - Pre-generated data files in data/ directory
    - Environment variables (see .env)
============================================================================
"""

import json
import os
import sys
from datetime import datetime, timedelta

from dotenv import load_dotenv
load_dotenv()

import oracledb

# ============================================================================
# Configuration
# ============================================================================

ORACLE_DSN = os.environ.get("DBCONNECTION")
ORACLE_USER = "prism"
ORACLE_PASSWORD = os.environ.get("DBPASSWORD")
ORACLE_WALLET_DIR = os.environ.get("ORACLE_WALLET_DIR")

# Data files directory (shared with the sibling adb/ directory, one
# level up from this script)
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
MAINTENANCE_LOGS_FILE = os.path.join(DATA_DIR, "maintenance_logs.json")
INSPECTION_REPORTS_FILE = os.path.join(DATA_DIR, "inspection_reports.json")

# ============================================================================
# Structural Data Definitions
# ============================================================================

DISTRICTS = [
    {
        "name": "Harbor District",
        "classification": "industrial",
        "population": 12400,
        "area_sq_km": 8.7,
        "description": "Waterfront industrial zone housing the city's primary port facilities, maritime infrastructure, and coastal monitoring systems."
    },
    {
        "name": "Meridian Heights",
        "classification": "residential",
        "population": 45200,
        "area_sq_km": 12.3,
        "description": "Primary residential district with mixed-density housing, neighborhood parks, and distributed utility infrastructure."
    },
    {
        "name": "Ironworks Quarter",
        "classification": "industrial",
        "population": 8900,
        "area_sq_km": 6.1,
        "description": "Heavy industrial zone containing power generation, water treatment, and waste management facilities."
    },
    {
        "name": "Central Commons",
        "classification": "mixed-use",
        "population": 31500,
        "area_sq_km": 4.2,
        "description": "City center with commercial towers, civic buildings, transit hubs, and high-density residential blocks."
    },
    {
        "name": "Greenfield Park",
        "classification": "residential",
        "population": 28700,
        "area_sq_km": 15.8,
        "description": "Suburban residential district with extensive green spaces, underground utility corridors, and distributed solar installations."
    },
    {
        "name": "Riverside Corridor",
        "classification": "commercial",
        "population": 19300,
        "area_sq_km": 5.4,
        "description": "Commercial and light industrial strip along the river, featuring warehousing, logistics facilities, and flood management infrastructure."
    },
    {
        "name": "Northgate Industrial",
        "classification": "industrial",
        "population": 5600,
        "area_sq_km": 9.9,
        "description": "Northern industrial park with chemical processing plants, rail freight terminals, and high-voltage power distribution."
    }
]

# Asset definitions: (name, asset_type, district_index, status, commissioned_date, description, specifications)
INFRASTRUCTURE_ASSETS = [
    # Bridges
    ("Harbor Bridge", "bridge", 0, "active", "1987-03-15",
     "Primary vehicular and pedestrian bridge spanning the harbor inlet. Four-lane capacity with dedicated pedestrian walkways.",
     {"spanLength_m": 485, "loadCapacity_t": 5000, "laneCount": 4, "material": "steel-concrete composite", "deckWidth_m": 22}),
    ("Meridian Overpass", "bridge", 1, "active", "2003-08-22",
     "Grade-separated highway overpass connecting Meridian Heights to Central Commons.",
     {"spanLength_m": 210, "loadCapacity_t": 3500, "laneCount": 2, "material": "pre-stressed concrete", "clearance_m": 5.2}),
    ("Riverside Pedestrian Bridge", "bridge", 5, "active", "2015-06-10",
     "Cable-stayed pedestrian and cyclist bridge crossing the river at Riverside Corridor.",
     {"spanLength_m": 165, "loadCapacity_t": 500, "laneCount": 0, "material": "steel cable-stayed", "deckWidth_m": 4.5}),

    # Substations
    ("Substation Gamma", "substation", 2, "active", "1995-11-01",
     "Primary high-voltage substation serving Ironworks Quarter and portions of Central Commons.",
     {"voltageRating_kv": 132, "transformerCount": 3, "peakCapacity_mw": 250, "coolingType": "ONAN/ONAF"}),
    ("Substation Delta", "substation", 6, "active", "2001-04-18",
     "Distribution substation for Northgate Industrial, handling heavy industrial loads.",
     {"voltageRating_kv": 66, "transformerCount": 2, "peakCapacity_mw": 120, "coolingType": "ONAF"}),
    ("Substation Epsilon", "substation", 3, "active", "2010-09-30",
     "Urban distribution substation embedded within Central Commons, serving commercial and residential loads.",
     {"voltageRating_kv": 33, "transformerCount": 4, "peakCapacity_mw": 80, "coolingType": "ONAN"}),

    # Pipelines
    ("Pipeline North-7", "pipeline", 6, "active", "1998-02-14",
     "High-pressure water main running from the northern reservoir through Northgate Industrial to Ironworks Quarter.",
     {"diameter_mm": 600, "material": "ductile iron", "pressureRating_kpa": 1200, "length_km": 12.4}),
    ("Pipeline South-3", "pipeline", 4, "active", "2005-07-20",
     "Medium-pressure distribution main serving Greenfield Park residential areas.",
     {"diameter_mm": 400, "material": "HDPE", "pressureRating_kpa": 800, "length_km": 8.1}),
    ("Harbor Outfall Main", "pipeline", 0, "active", "1992-12-05",
     "Treated wastewater outfall pipeline extending from the Ironworks treatment plant to the harbor discharge point.",
     {"diameter_mm": 900, "material": "reinforced concrete", "pressureRating_kpa": 400, "length_km": 3.2}),
    ("Central Gas Distribution", "pipeline", 3, "active", "2008-03-11",
     "Natural gas distribution network serving Central Commons commercial and residential buildings.",
     {"diameter_mm": 200, "material": "steel", "pressureRating_kpa": 700, "length_km": 6.8}),

    # Sensors
    ("Harbor Bridge Sensor Array A", "sensor", 0, "active", "2018-05-14",
     "Structural health monitoring array on Harbor Bridge north pylon. Measures vibration, strain, and temperature.",
     {"sensorTypes": ["accelerometer", "strain gauge", "thermocouple"], "sampleRate_hz": 100, "channels": 24, "powerSource": "solar"}),
    ("Harbor Bridge Sensor Array B", "sensor", 0, "active", "2018-05-14",
     "Structural health monitoring array on Harbor Bridge south pylon and deck midspan.",
     {"sensorTypes": ["accelerometer", "strain gauge", "displacement"], "sampleRate_hz": 100, "channels": 18, "powerSource": "solar"}),
    ("Flood Gauge Station R1", "sensor", 5, "active", "2016-01-20",
     "River level and flow rate monitoring station at the upstream boundary of Riverside Corridor.",
     {"sensorTypes": ["ultrasonic level", "doppler flow", "rain gauge"], "sampleRate_hz": 1, "channels": 6, "powerSource": "mains with battery backup"}),
    ("Air Quality Monitor NI-01", "sensor", 6, "active", "2020-11-08",
     "Continuous air quality monitoring station at the perimeter of Northgate Industrial.",
     {"sensorTypes": ["PM2.5", "PM10", "NO2", "SO2", "O3", "CO"], "sampleRate_hz": 0.1, "channels": 8, "powerSource": "mains"}),
    ("Seismic Station CC-01", "sensor", 3, "active", "2019-07-15",
     "Strong-motion seismic sensor installed at the base of the Central Commons transit hub.",
     {"sensorTypes": ["triaxial accelerometer"], "sampleRate_hz": 200, "channels": 3, "powerSource": "mains with UPS"}),

    # Communication Towers
    ("Comms Tower Alpha", "communication_tower", 1, "active", "2012-08-30",
     "Primary communications tower for Meridian Heights, hosting cellular, emergency services, and IoT network antennas.",
     {"height_m": 65, "antennaCount": 12, "coverageRadius_km": 8, "backhaul": "fiber"}),
    ("Comms Tower Beta", "communication_tower", 6, "active", "2014-03-22",
     "Industrial communications tower serving Northgate Industrial with SCADA telemetry and process control networks.",
     {"height_m": 45, "antennaCount": 8, "coverageRadius_km": 5, "backhaul": "fiber + microwave"}),
    ("Harbor Relay Station", "communication_tower", 0, "active", "2017-09-01",
     "Maritime communications relay providing VHF, AIS, and port operations connectivity.",
     {"height_m": 35, "antennaCount": 6, "coverageRadius_km": 15, "backhaul": "fiber"}),

    # Water Treatment
    ("Ironworks Water Treatment Plant", "treatment_plant", 2, "active", "1990-06-15",
     "Municipal wastewater treatment facility processing flows from Central Commons, Meridian Heights, and Ironworks Quarter.",
     {"capacity_mld": 120, "treatmentLevel": "tertiary", "processType": "activated sludge with UV disinfection", "sludgeHandling": "anaerobic digestion"}),

    # Pump Stations
    ("Riverside Pump Station", "pump_station", 5, "active", "2007-10-12",
     "Stormwater pump station managing flood risk along the Riverside Corridor.",
     {"pumpCount": 4, "totalCapacity_ls": 2500, "backupPower": "diesel generator", "activationTrigger": "river level > 4.2m"}),
    ("Greenfield Booster Station", "pump_station", 4, "active", "2009-01-28",
     "Water pressure booster station maintaining supply pressure across the elevated sections of Greenfield Park.",
     {"pumpCount": 3, "totalCapacity_ls": 800, "backupPower": "diesel generator", "activationTrigger": "pressure < 350 kPa"}),

    # Retaining Walls
    ("Harbor Seawall Section A", "retaining_wall", 0, "active", "1985-04-20",
     "Concrete seawall protecting Harbor District infrastructure from tidal and storm surge events.",
     {"length_m": 450, "height_m": 6.5, "material": "reinforced concrete with steel sheet piling", "designWaveHeight_m": 3.5}),
    ("Meridian Cut Retaining Wall", "retaining_wall", 1, "active", "2003-08-22",
     "Reinforced earth retaining wall along the highway cut for Meridian Overpass approaches.",
     {"length_m": 280, "height_m": 8.0, "material": "mechanically stabilized earth", "designLoad_kpa": 20}),

    # Reservoirs
    ("Northern Reservoir", "reservoir", 6, "active", "1978-09-10",
     "Primary potable water storage reservoir supplying the northern half of the city via Pipeline North-7.",
     {"capacity_ml": 85, "depth_m": 12, "coverType": "floating cover", "treatmentOnsite": False}),

    # Solar Installations
    ("Greenfield Solar Array", "solar_installation", 4, "active", "2021-02-15",
     "Distributed rooftop and ground-mount solar installation across Greenfield Park public buildings.",
     {"peakCapacity_kw": 2400, "panelCount": 6000, "inverterType": "string", "annualYield_mwh": 3800}),

    # Rail
    ("Northgate Freight Terminal", "rail_terminal", 6, "active", "1982-11-30",
     "Rail freight terminal handling bulk materials for Northgate Industrial facilities.",
     {"trackCount": 6, "maxTrainLength_m": 800, "craneCapacity_t": 50, "annualThroughput_t": 2500000}),
]

# Connections: (from_asset_name, to_asset_name, connection_type, description)
ASSET_CONNECTIONS = [
    ("Harbor Bridge Sensor Array A", "Harbor Bridge", "monitors", "North pylon structural health monitoring"),
    ("Harbor Bridge Sensor Array B", "Harbor Bridge", "monitors", "South pylon and deck midspan monitoring"),
    ("Flood Gauge Station R1", "Riverside Pump Station", "monitors", "River level triggers pump activation"),
    ("Air Quality Monitor NI-01", "Northgate Freight Terminal", "monitors", "Perimeter air quality monitoring for freight operations"),
    ("Seismic Station CC-01", "Meridian Overpass", "monitors", "Strong-motion monitoring for structural assessment"),
    ("Substation Gamma", "Ironworks Water Treatment Plant", "powers", "Primary power supply for treatment plant operations"),
    ("Substation Gamma", "Harbor Bridge", "powers", "Bridge lighting and sensor power supply"),
    ("Substation Delta", "Northgate Freight Terminal", "powers", "Power supply for terminal cranes and facilities"),
    ("Substation Delta", "Comms Tower Beta", "powers", "Power supply for industrial communications"),
    ("Substation Epsilon", "Seismic Station CC-01", "powers", "Mains power with UPS backup"),
    ("Greenfield Solar Array", "Greenfield Booster Station", "powers", "Supplementary solar power for booster pumps"),
    ("Northern Reservoir", "Pipeline North-7", "feeds", "Potable water supply from reservoir to distribution"),
    ("Pipeline North-7", "Ironworks Water Treatment Plant", "feeds", "Raw water supply to treatment facility"),
    ("Pipeline South-3", "Greenfield Booster Station", "feeds", "Distribution main to pressure booster"),
    ("Ironworks Water Treatment Plant", "Harbor Outfall Main", "feeds", "Treated effluent discharge to harbor"),
    ("Riverside Pump Station", "Flood Gauge Station R1", "connects-to", "Pump station intake at gauge location"),
    ("Comms Tower Alpha", "Comms Tower Beta", "connects-to", "Microwave backhaul link between towers"),
    ("Comms Tower Beta", "Harbor Relay Station", "connects-to", "Network relay for port operations"),
    ("Comms Tower Alpha", "Harbor Bridge Sensor Array A", "connects-to", "IoT data backhaul from bridge sensors"),
    ("Comms Tower Alpha", "Harbor Bridge Sensor Array B", "connects-to", "IoT data backhaul from bridge sensors"),
    ("Comms Tower Beta", "Air Quality Monitor NI-01", "connects-to", "Telemetry data backhaul"),
    ("Harbor Seawall Section A", "Harbor Bridge", "supports", "Seawall protects bridge abutment foundations"),
    ("Meridian Cut Retaining Wall", "Meridian Overpass", "supports", "Retaining wall stabilizes overpass approach embankments"),
    ("Central Gas Distribution", "Substation Epsilon", "connects-to", "Gas supply for backup generation at substation"),
    ("Pipeline North-7", "Pipeline South-3", "connects-to", "Interconnection valve at distribution junction"),

    # Cross-component connections (bridge the two graph clusters)
    ("Substation Gamma", "Substation Epsilon", "powers", "132kV to 33kV step-down feed via transmission line T4-Central"),
    ("Comms Tower Alpha", "Seismic Station CC-01", "connects-to", "Seismic data telemetry backhaul to central monitoring"),
    ("Flood Gauge Station R1", "Riverside Pedestrian Bridge", "monitors", "River level monitoring at pedestrian bridge crossing"),
]

OPERATIONAL_PROCEDURES = [
    {"procedureId": "SOP-HV-001", "title": "High Voltage Substation Inspection Protocol", "category": "electrical", "version": "3.2", "lastRevised": "2025-11-15", "estimatedDuration_min": 180, "requiredPersonnel": 3, "applicableAssetTypes": ["substation"], "safetyChecklist": ["Verify all circuits de-energized and locked out", "Confirm grounding cables attached at all work points", "PPE inspection: arc-flash suit (min CAT 3), insulated gloves (Class 2), face shield", "Verify rescue equipment staged and accessible", "Confirm communication with control room established"], "equipment": ["thermal imaging camera", "insulation resistance tester (megger)", "partial discharge detector", "oil sampling kit", "digital multimeter (CAT IV rated)"], "steps": [{"order": 1, "action": "Perform visual inspection of all transformer bushings and insulators", "notes": "Document any discoloration, cracks, or oil leaks with photos"}, {"order": 2, "action": "Conduct thermal scan of all bus connections and switchgear", "notes": "Flag any connection with temperature differential exceeding 10\u00b0C above ambient"}, {"order": 3, "action": "Perform insulation resistance testing on each transformer winding", "notes": "Minimum acceptable reading: 1 G\u03a9 at 5 kV test voltage"}, {"order": 4, "action": "Collect oil samples from each transformer for dissolved gas analysis", "notes": "Use clean syringes; label with transformer ID and date"}, {"order": 5, "action": "Inspect cooling systems: fans, radiators, oil pumps", "notes": "Run each fan group for 2 minutes and verify operation"}, {"order": 6, "action": "Check protection relay settings and test trip circuits", "notes": "Do not perform live trip tests without control room authorization"}, {"order": 7, "action": "Inspect earthing system and measure ground resistance", "notes": "Maximum acceptable ground resistance: 1 \u03a9"}], "escalation": {"contact": "Grid Operations Center", "phone": "555-0142", "conditions": ["Evidence of active arcing", "Transformer oil level below minimum mark", "Ground fault detected", "Protection relay failure"]}},
    {"procedureId": "SOP-BR-001", "title": "Bridge Structural Assessment Procedure", "category": "structural", "version": "2.1", "lastRevised": "2025-08-20", "estimatedDuration_min": 240, "requiredPersonnel": 4, "applicableAssetTypes": ["bridge"], "safetyChecklist": ["Traffic management plan approved and signage deployed", "Fall protection harnesses inspected and worn by all personnel", "Under-bridge inspection platform pre-positioned and load-tested", "Marine traffic notified if working over navigable water", "Weather check: postpone if wind exceeds 40 km/h or lightning within 10 km"], "equipment": ["Schmidt rebound hammer", "ultrasonic thickness gauge", "crack width comparator cards", "half-cell potential meter", "drone with high-resolution camera", "GPS-enabled measurement tools"], "steps": [{"order": 1, "action": "Conduct drone survey of entire bridge deck and superstructure", "notes": "Capture ortho-mosaic imagery at minimum 2 cm/pixel resolution"}, {"order": 2, "action": "Inspect all expansion joints for debris, damage, and alignment", "notes": "Measure joint gap at 3 points per joint and compare to design values"}, {"order": 3, "action": "Perform concrete condition survey on substructure elements", "notes": "Use Schmidt hammer at 10 test points per pier; record rebound numbers"}, {"order": 4, "action": "Measure crack widths on all visible cracks exceeding 0.1 mm", "notes": "Map crack locations on structural drawings; flag any crack > 0.3 mm"}, {"order": 5, "action": "Conduct ultrasonic thickness measurements on steel elements", "notes": "Test at 5 points per member; flag any section loss exceeding 10%"}, {"order": 6, "action": "Inspect bearing assemblies for corrosion, displacement, and lubrication", "notes": "Photograph each bearing; note any lateral displacement > 5 mm"}, {"order": 7, "action": "Assess drainage system for blockages and erosion damage", "notes": "Flush each scupper and downpipe; verify discharge at outfall"}, {"order": 8, "action": "Review and update sensor calibration records for installed monitoring equipment", "notes": "Cross-reference live sensor readings with manual measurements"}], "escalation": {"contact": "Structural Engineering Division", "phone": "555-0187", "conditions": ["Any crack exceeding 1.0 mm width", "Section loss exceeding 25%", "Bearing displacement exceeding 15 mm", "Visible reinforcement corrosion"]}},
    {"procedureId": "SOP-PL-001", "title": "Pressurized Pipeline Integrity Assessment", "category": "pipeline", "version": "4.0", "lastRevised": "2025-10-02", "estimatedDuration_min": 300, "requiredPersonnel": 3, "applicableAssetTypes": ["pipeline"], "safetyChecklist": ["Pipeline depressurized and isolated at both ends (double block and bleed)", "Atmospheric monitoring: confirm no hazardous gases (LEL < 10%, O2 19.5-23.5%)", "Confined space entry permit obtained if entering valve chambers", "Traffic management in place for any road crossings", "Emergency shutdown procedure reviewed with all team members"], "equipment": ["inline inspection pig launcher/receiver", "magnetic flux leakage (MFL) tool", "pipeline CCTV crawler", "ultrasonic wall thickness gauge", "pressure test pump and chart recorder"], "steps": [{"order": 1, "action": "Verify pipeline isolation and depressurization at all boundary valves", "notes": "Record valve positions and lock-out/tag-out details"}, {"order": 2, "action": "Launch CCTV inspection crawler from upstream access point", "notes": "Record video with distance counter; note any anomalies with timestamps"}, {"order": 3, "action": "Perform ultrasonic wall thickness measurements at accessible locations", "notes": "Minimum 5 readings per pipe section; focus on bends and joints"}, {"order": 4, "action": "Inspect all valve chambers for leaks, corrosion, and structural integrity", "notes": "Check valve stem packing, flange bolts, and chamber ventilation"}, {"order": 5, "action": "Conduct hydrostatic pressure test at 1.5x operating pressure", "notes": "Hold for minimum 2 hours; acceptable pressure drop: < 0.5%"}, {"order": 6, "action": "Inspect cathodic protection system: anodes, rectifiers, test stations", "notes": "Measure pipe-to-soil potential at each test station; target: -850 mV to -1200 mV (Cu/CuSO4)"}, {"order": 7, "action": "Survey pipeline route for surface settlement, erosion, or third-party damage", "notes": "Walk full route; compare surface levels to baseline survey"}], "escalation": {"contact": "Water Infrastructure Emergency Line", "phone": "555-0129", "conditions": ["Wall thickness below 60% of nominal", "Failed hydrostatic test", "Active leak detected", "Cathodic protection failure across multiple stations"]}},
    {"procedureId": "SOP-EM-001", "title": "Emergency Pipeline Leak Response", "category": "emergency", "version": "5.1", "lastRevised": "2026-01-10", "estimatedDuration_min": 0, "requiredPersonnel": 4, "applicableAssetTypes": ["pipeline", "pump_station"], "safetyChecklist": ["Establish exclusion zone: minimum 25 m radius from leak source", "Atmospheric monitoring continuous at exclusion zone boundary", "Emergency services notified if gas or hazardous material involved", "Downstream consumers notified of potential supply interruption", "PPE: waterproof suit, respiratory protection if gas risk, steel-toe boots"], "equipment": ["pipe repair clamps (assorted sizes)", "portable pump for dewatering", "pipe freezing kit", "leak sealing compound", "portable generator and lighting"], "steps": [{"order": 1, "action": "Assess leak severity and classify", "notes": "Category 1 (spray/gush) requires immediate isolation"}, {"order": 2, "action": "Isolate the affected section using upstream and downstream valves", "notes": "Coordinate with SCADA control room"}, {"order": 3, "action": "Establish dewatering and containment at the leak site", "notes": "Prevent uncontrolled runoff"}, {"order": 4, "action": "Apply temporary repair appropriate to pipe material and pressure", "notes": "Replace with permanent repair within 72 hours"}, {"order": 5, "action": "Restore pressure gradually and monitor for 30 minutes", "notes": "Increase in 25% increments"}, {"order": 6, "action": "Document incident with GPS, photos, and cause assessment", "notes": "Submit report within 24 hours"}], "escalation": {"contact": "Emergency Operations Center", "phone": "555-0911", "conditions": ["Category 1 leak on main exceeding 300 mm", "Any gas leak", "Contamination risk to potable supply"]}},
    {"procedureId": "SOP-CT-001", "title": "Communications Tower Routine Maintenance", "category": "communications", "version": "2.0", "lastRevised": "2025-06-18", "estimatedDuration_min": 150, "requiredPersonnel": 2, "applicableAssetTypes": ["communication_tower"], "safetyChecklist": ["Tower climbing certification verified", "Fall arrest system inspected", "RF exposure assessment completed", "Weather check: no climbing if wind > 50 km/h", "Rescue plan in place"], "equipment": ["cable analyzer", "fiber optic power meter and OTDR", "torque wrench set", "coaxial connector toolkit", "tower-rated tool lanyard system"], "steps": [{"order": 1, "action": "Inspect tower structure: legs, bracing, bolted connections, foundation", "notes": "Check for corrosion, loose bolts, cracked welds"}, {"order": 2, "action": "Inspect all antenna mounts, brackets, and alignment", "notes": "Verify azimuth and tilt match RF design"}, {"order": 3, "action": "Test all coaxial and fiber optic cable runs", "notes": "Sweep test coax; OTDR test fiber"}, {"order": 4, "action": "Inspect obstruction lighting", "notes": "Replace failed lamps immediately"}, {"order": 5, "action": "Inspect grounding system", "notes": "Maximum 5 ohm for telecom towers"}, {"order": 6, "action": "Clean and inspect equipment shelter", "notes": "Check HVAC, UPS, batteries, fire suppression"}], "escalation": {"contact": "Network Operations Center", "phone": "555-0165", "conditions": ["Structural damage", "Obstruction lighting failure", "Ground resistance exceeding 10 ohm"]}},
    {"procedureId": "SOP-WTP-001", "title": "Water Treatment Plant Process Audit", "category": "water-treatment", "version": "3.0", "lastRevised": "2025-09-05", "estimatedDuration_min": 360, "requiredPersonnel": 3, "applicableAssetTypes": ["treatment_plant"], "safetyChecklist": ["Chemical handling PPE available", "Safety showers and eyewash tested", "Atmospheric monitoring in enclosed areas", "Chlorine gas detection verified", "Emergency spill kit staged"], "equipment": ["portable turbidity meter", "pH/ORP meter", "dissolved oxygen meter", "sample bottles", "portable flow meter"], "steps": [{"order": 1, "action": "Review SCADA trends for previous 30 days", "notes": "Flag any exceedances"}, {"order": 2, "action": "Inspect primary treatment", "notes": "Check scrapers, scum removal, sludge blanket"}, {"order": 3, "action": "Inspect secondary treatment", "notes": "Verify DO setpoints"}, {"order": 4, "action": "Inspect tertiary treatment and disinfection", "notes": "Check UV lamp intensity"}, {"order": 5, "action": "Audit chemical storage", "notes": "Verify inventory"}, {"order": 6, "action": "Review laboratory QA/QC", "notes": "Verify calibration records"}, {"order": 7, "action": "Inspect sludge handling", "notes": "Check digester gas production"}, {"order": 8, "action": "Review compliance reporting", "notes": "Ensure reports submitted on time"}], "escalation": {"contact": "Environmental Compliance Manager", "phone": "555-0134", "conditions": ["Effluent exceeding permit limits", "Chemical spill", "UV system failure"]}},
    {"procedureId": "SOP-FLD-001", "title": "Flood Event Response and Pump Station Operations", "category": "emergency", "version": "4.2", "lastRevised": "2025-12-01", "estimatedDuration_min": 0, "requiredPersonnel": 3, "applicableAssetTypes": ["pump_station", "sensor"], "safetyChecklist": ["Swift-water rescue team on standby", "Exclusion zone around wet well", "Backup generator fuel > 75%", "Communication with EOC established", "Road closure requests submitted"], "equipment": ["portable submersible pump", "sandbags and flood barriers", "portable generator", "water level data logger", "satellite phone"], "steps": [{"order": 1, "action": "Activate flood monitoring protocol", "notes": "Begin at river level > 3.5 m"}, {"order": 2, "action": "Pre-position portable pumps and barriers", "notes": "Priority: Riverside underpass, Harbor low points"}, {"order": 3, "action": "Verify all permanent pump stations operational", "notes": "Run each pump for 2 minutes"}, {"order": 4, "action": "Activate Riverside Pump Station at trigger level", "notes": "Confirm SCADA receiving data"}, {"order": 5, "action": "Deploy field crew to monitor flow paths", "notes": "Focus on trash screens and culverts"}, {"order": 6, "action": "Post-event cleanup and inspection", "notes": "Document high-water marks with GPS"}], "escalation": {"contact": "Emergency Operations Center", "phone": "555-0911", "conditions": ["River level exceeding 5.5 m", "Pump station failure during event", "Road inundation"]}},
    {"procedureId": "SOP-SW-001", "title": "Seawall and Retaining Wall Annual Inspection", "category": "structural", "version": "1.3", "lastRevised": "2025-07-22", "estimatedDuration_min": 200, "requiredPersonnel": 2, "applicableAssetTypes": ["retaining_wall"], "safetyChecklist": ["Tidal schedule reviewed", "Fall protection for crest work", "Marine exclusion zone if waterside", "Hard hat and high-vis at all times", "First aid kit with hypothermia blanket"], "equipment": ["crack monitoring pins and caliper", "ground-penetrating radar", "survey-grade GPS", "underwater camera", "concrete coring drill"], "steps": [{"order": 1, "action": "Survey wall crest and toe levels", "notes": "Flag settlement > 15 mm"}, {"order": 2, "action": "Visual inspection of wall face", "notes": "Map all defects on elevation drawings"}, {"order": 3, "action": "Install or read crack monitoring pins", "notes": "Record to 0.05 mm precision"}, {"order": 4, "action": "Inspect drainage systems", "notes": "Blocked weepholes indicate failure"}, {"order": 5, "action": "Conduct GPR survey along crest", "notes": "Focus near stormwater outfalls"}, {"order": 6, "action": "Inspect toe protection at low tide", "notes": "Note scour depth measurements"}], "escalation": {"contact": "Coastal Engineering Division", "phone": "555-0176", "conditions": ["Settlement > 50 mm", "Crack growth > 0.5 mm/year", "Void detected behind wall"]}},
    {"procedureId": "SOP-SOL-001", "title": "Solar Installation Performance Audit", "category": "electrical", "version": "1.1", "lastRevised": "2025-05-30", "estimatedDuration_min": 120, "requiredPersonnel": 2, "applicableAssetTypes": ["solar_installation"], "safetyChecklist": ["DC isolation verified", "Arc-flash PPE for inverter access", "Roof access harness and anchors", "No work on wet panels", "Fire isolation switches accessible"], "equipment": ["IV curve tracer", "thermal imaging camera", "digital multimeter (CAT III)", "irradiance meter", "insulation resistance tester"], "steps": [{"order": 1, "action": "Review monitoring data vs expected yield", "notes": "Flag output < 90% expected"}, {"order": 2, "action": "Conduct thermal survey of panel strings", "notes": "Identify hot spots"}, {"order": 3, "action": "Perform IV curve tracing on sample strings", "notes": "Flag degradation > 2%/year"}, {"order": 4, "action": "Inspect inverter operation", "notes": "Check THD < 5%, PF > 0.95"}, {"order": 5, "action": "Inspect racking and grounding", "notes": "Check for corrosion"}, {"order": 6, "action": "Clean panels if soiling > 5%", "notes": "Deionized water only"}], "escalation": {"contact": "Renewable Energy Operations Manager", "phone": "555-0198", "conditions": ["Inverter failure", "DC ground fault", "Hot spot > 30C differential"]}},
]


# ============================================================================
# Database Operations
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


def cleanup_tables(cursor):
    """Delete all data from tables in the correct order (children first) for re-runs."""
    print("Cleaning up existing data...")
    tables = [
        "document_chunks",
        "inspection_findings",
        "inspection_reports",
        "asset_connections",
        "maintenance_logs",
        "operational_procedures",
        "infrastructure_assets",
        "districts",
    ]
    for table in tables:
        cursor.execute(f"DELETE FROM {table}")
        count = cursor.rowcount
        print(f"  Deleted {count} rows from {table}.")
    print("  Cleanup complete.")


def insert_districts(cursor):
    """Insert district records."""
    print("Inserting districts...")
    for d in DISTRICTS:
        cursor.execute("""
            INSERT INTO districts (name, classification, population, area_sq_km, description)
            VALUES (:name, :classification, :population, :area_sq_km, :description)
        """, d)
    print(f"  Inserted {len(DISTRICTS)} districts.")


def insert_assets(cursor):
    """Insert infrastructure asset records. Returns a mapping of asset name to asset_id."""
    print("Inserting infrastructure assets...")

    cursor.execute("SELECT district_id, name FROM districts")
    district_map = {row[1]: row[0] for row in cursor.fetchall()}

    for asset in INFRASTRUCTURE_ASSETS:
        name, asset_type, district_idx, status, comm_date, description, specs = asset
        district_name = DISTRICTS[district_idx]["name"]
        district_id = district_map[district_name]

        cursor.execute("""
            INSERT INTO infrastructure_assets
                (district_id, name, asset_type, status, commissioned_date, description, specifications)
            VALUES
                (:district_id, :name, :asset_type, :status,
                 TO_DATE(:commissioned_date, 'YYYY-MM-DD'), :description,
                 JSON(:specifications))
        """, {
            "district_id": district_id,
            "name": name,
            "asset_type": asset_type,
            "status": status,
            "commissioned_date": comm_date,
            "description": description,
            "specifications": json.dumps(specs),
        })

    cursor.execute("SELECT asset_id, name FROM infrastructure_assets")
    asset_map = {row[1]: row[0] for row in cursor.fetchall()}

    print(f"  Inserted {len(INFRASTRUCTURE_ASSETS)} assets.")
    return asset_map


def insert_connections(cursor, asset_map):
    """Insert asset connection records."""
    print("Inserting asset connections...")
    count = 0
    for conn in ASSET_CONNECTIONS:
        from_name, to_name, conn_type, description = conn
        if from_name not in asset_map or to_name not in asset_map:
            print(f"  WARNING: Skipping connection '{from_name}' -> '{to_name}': asset not found")
            continue
        cursor.execute("""
            INSERT INTO asset_connections
                (from_asset_id, to_asset_id, connection_type, description)
            VALUES
                (:from_id, :to_id, :conn_type, :description)
        """, {
            "from_id": asset_map[from_name],
            "to_id": asset_map[to_name],
            "conn_type": conn_type,
            "description": description
        })
        count += 1
    print(f"  Inserted {count} connections.")


def insert_procedures(cursor):
    """Insert operational procedure documents into the JSON collection table."""
    print("Inserting operational procedures...")
    for proc in OPERATIONAL_PROCEDURES:
        cursor.execute("""
            INSERT INTO operational_procedures (data)
            VALUES (JSON(:doc))
        """, {"doc": json.dumps(proc)})
    print(f"  Inserted {len(OPERATIONAL_PROCEDURES)} procedures.")


# ============================================================================
# Load Pre-Generated Content from JSON Files
# ============================================================================

def load_maintenance_logs(cursor, asset_map):
    """Load maintenance logs from the pre-generated JSON file."""
    print(f"Loading maintenance logs from {MAINTENANCE_LOGS_FILE}...")

    with open(MAINTENANCE_LOGS_FILE, "r") as f:
        logs = json.load(f)

    inserted = 0
    skipped = 0
    for log in logs:
        asset_name = log["asset_name"]
        if asset_name not in asset_map:
            print(f"  WARNING: Skipping log for unknown asset '{asset_name}'")
            skipped += 1
            continue

        log_date = datetime.now() - timedelta(days=log.get("days_ago", 1))
        cursor.execute("""
            INSERT INTO maintenance_logs (asset_id, log_date, severity, narrative)
            VALUES (:asset_id, :log_date, :severity, :narrative)
        """, {
            "asset_id": asset_map[asset_name],
            "log_date": log_date,
            "severity": log["severity"],
            "narrative": log["narrative"],
        })
        inserted += 1

    print(f"  Inserted {inserted} maintenance logs.")
    if skipped:
        print(f"  Skipped {skipped} logs (unknown asset names).")


def load_inspection_reports(cursor, asset_map):
    """Load inspection reports and findings from the pre-generated JSON file."""
    print(f"Loading inspection reports from {INSPECTION_REPORTS_FILE}...")

    with open(INSPECTION_REPORTS_FILE, "r") as f:
        reports = json.load(f)

    total_reports = 0
    total_findings = 0
    skipped = 0

    for report in reports:
        asset_name = report["asset_name"]
        if asset_name not in asset_map:
            print(f"  WARNING: Skipping report for unknown asset '{asset_name}'")
            skipped += 1
            continue

        inspect_date = datetime.now() - timedelta(days=report.get("days_ago", 1))

        cursor.execute("""
            INSERT INTO inspection_reports
                (asset_id, inspector, inspect_date, overall_grade, summary)
            VALUES
                (:asset_id, :inspector, :inspect_date, :overall_grade, :summary)
        """, {
            "asset_id": asset_map[asset_name],
            "inspector": report["inspector"],
            "inspect_date": inspect_date,
            "overall_grade": report["overall_grade"],
            "summary": report["summary"],
        })

        # Fetch the generated report_id
        cursor.execute("""
            SELECT MAX(report_id) FROM inspection_reports
            WHERE asset_id = :aid AND inspector = :insp
        """, {"aid": asset_map[asset_name], "insp": report["inspector"]})
        report_id = cursor.fetchone()[0]

        for finding in report.get("findings", []):
            cursor.execute("""
                INSERT INTO inspection_findings
                    (report_id, category, severity, description, recommendation)
                VALUES
                    (:report_id, :category, :severity, :description, :recommendation)
            """, {
                "report_id": report_id,
                "category": finding["category"],
                "severity": finding["severity"],
                "description": finding["description"],
                "recommendation": finding["recommendation"],
            })
            total_findings += 1

        total_reports += 1

    print(f"  Inserted {total_reports} inspection reports.")
    print(f"  Inserted {total_findings} inspection findings.")
    if skipped:
        print(f"  Skipped {skipped} reports (unknown asset names).")


# ============================================================================
# Main
# ============================================================================

def main():
    print("=" * 72)
    print("  PRISM: Seed Data Loader")
    print("=" * 72)
    print()

    # Validate configuration
    missing = []
    if not ORACLE_DSN:
        missing.append("ORACLE_DSN")
    if not ORACLE_PASSWORD:
        missing.append("ORACLE_PASSWORD")
    if missing:
        print(f"ERROR: Missing required environment variables: {', '.join(missing)}")
        sys.exit(1)

    # Check for data files
    missing_files = []
    if not os.path.isfile(MAINTENANCE_LOGS_FILE):
        missing_files.append(MAINTENANCE_LOGS_FILE)
    if not os.path.isfile(INSPECTION_REPORTS_FILE):
        missing_files.append(INSPECTION_REPORTS_FILE)
    if missing_files:
        print("ERROR: Pre-generated data files not found:")
        for f in missing_files:
            print(f"  {f}")
        print()
        print("Run 'python prism-generate.py' first to generate the data files.")
        sys.exit(1)

    # Connect to database
    print("Connecting to Oracle database...")
    conn = get_connection()
    cursor = conn.cursor()
    print("  Connected.")

    # Clean up any existing data from previous runs
    print("\n--- Phase 0: Cleanup ---")
    cleanup_tables(cursor)
    conn.commit()

    # Insert structural data
    print("\n--- Phase 1: Structural Data ---")
    insert_districts(cursor)
    asset_map = insert_assets(cursor)
    insert_connections(cursor, asset_map)
    insert_procedures(cursor)
    conn.commit()
    print("\nStructural data committed.")

    # Load pre-generated content from JSON files
    print("\n--- Phase 2: Load Generated Content ---")
    load_maintenance_logs(cursor, asset_map)
    conn.commit()
    print("Maintenance logs committed.")

    load_inspection_reports(cursor, asset_map)
    conn.commit()
    print("Inspection reports committed.")

    # Summary
    print("\n--- Summary ---")
    for table_name in ["districts", "infrastructure_assets", "operational_procedures",
                       "maintenance_logs", "inspection_reports", "inspection_findings",
                       "asset_connections"]:
        cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
        count = cursor.fetchone()[0]
        print(f"  {table_name:30s} {count:>6d} rows")

    cursor.close()
    conn.close()

    print()
    print("=" * 72)
    print("  Seed data loading complete.")
    print("  Next step: Run python prism-ingest.py to vectorize content.")
    print("=" * 72)


if __name__ == "__main__":
    main()
