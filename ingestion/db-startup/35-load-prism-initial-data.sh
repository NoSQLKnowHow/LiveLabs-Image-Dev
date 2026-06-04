#!/bin/bash
set -euo pipefail

# PRISM SQL*Plus seed data loader.
#
# This script loads the PRISM seed data without Python. It expects the PRISM
# schema tables to already exist, which this repo creates in
# 30-create-prism-db-objects.sh. Because this file is named
# 35-load-prism-initial-data.sh, Oracle container startup ordering will run it
# after the schema creation script.
#
# Host example:
#   DBPASSWORD='...' DBCONNECTION='localhost:1521/freepdb1' ./35-load-prism-initial-data.sh
#
# DB container example:
#   DBPASSWORD='...' DBCONNECTION='localhost:1521/freepdb1' /opt/oracle/scripts/startup/35-load-prism-initial-data.sh

DBUSER="${DBUSER:-PRISM}"
DBPASSWORD="${DBPASSWORD:-${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-Welcome202626ai}}}"
DBCONNECTION="${DBCONNECTION:-localhost:1521/freepdb1}"
DATA_DIR="${PRISM_DATA_DIR:-/opt/oracle/scripts/startup/data}"
DIRECTORY_NAME="${PRISM_DATA_DIRECTORY_NAME:-PRISM_STARTUP_DATA}"
SYS_CONNECT="${SYS_CONNECT:-sys/${DBPASSWORD}@${DBCONNECTION} as sysdba}"

if [[ -z "${DBPASSWORD}" ]]; then
  echo "DBPASSWORD, APP_DB_ADMIN_PWD, and ORACLE_PWD are all empty; cannot connect."
  exit 1
fi

echo "========================================================================"
echo "  PRISM: SQL*Plus Seed Data Loader"
echo "========================================================================"
echo

echo "Preparing Oracle directory ${DIRECTORY_NAME} for ${DATA_DIR} ..."
sqlplus -s "${SYS_CONNECT}" <<SQL
whenever sqlerror exit sql.sqlcode;
set define off
set serveroutput on

create or replace directory ${DIRECTORY_NAME} as '${DATA_DIR}';
grant read on directory ${DIRECTORY_NAME} to ${DBUSER};

prompt Directory ${DIRECTORY_NAME} is ready.
exit;
SQL

echo "Loading PRISM seed data with SQL*Plus ..."
sqlplus -s "${DBUSER}/${DBPASSWORD}@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

alter session set current_schema = ${DBUSER};

declare
  c_directory constant varchar2(128) := '${DIRECTORY_NAME}';
  l_json clob;
  l_file bfile;
  l_dest_offset integer;
  l_src_offset integer;
  l_lang_context integer;
  l_warning integer;
  l_count number;
  l_asset_id infrastructure_assets.asset_id%type;
  l_report_id inspection_reports.report_id%type;
  l_total number;
  l_inserted number;
  l_skipped number;
  l_findings number;
  l_error_detail varchar2(4000);

  procedure reset_json is
  begin
    if l_json is not null and dbms_lob.istemporary(l_json) = 1 then
      dbms_lob.freetemporary(l_json);
    end if;
    dbms_lob.createtemporary(l_json, true);
  end;

  procedure append_json(p_text in varchar2) is
  begin
    dbms_lob.append(l_json, to_clob(p_text));
  end;

  function load_json_file(p_file_name in varchar2) return clob is
    l_result clob;
  begin
    l_file := bfilename(c_directory, p_file_name);
    dbms_lob.createtemporary(l_result, true);
    l_dest_offset := 1;
    l_src_offset := 1;
    l_lang_context := dbms_lob.default_lang_ctx;

    dbms_lob.fileopen(l_file, dbms_lob.file_readonly);
    dbms_lob.loadclobfromfile(
      dest_lob     => l_result,
      src_bfile    => l_file,
      amount       => dbms_lob.getlength(l_file),
      dest_offset  => l_dest_offset,
      src_offset   => l_src_offset,
      bfile_csid   => dbms_lob.default_csid,
      lang_context => l_lang_context,
      warning      => l_warning
    );
    dbms_lob.fileclose(l_file);
    return l_result;
  exception
    when others then
      if dbms_lob.fileisopen(l_file) = 1 then
        dbms_lob.fileclose(l_file);
      end if;
      if dbms_lob.istemporary(l_result) = 1 then
        dbms_lob.freetemporary(l_result);
      end if;
      raise;
  end;
begin
  dbms_output.put_line('--- Phase 0: Cleanup ---');

  delete from document_chunks;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from document_chunks.');
  delete from inspection_findings;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from inspection_findings.');
  delete from inspection_reports;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from inspection_reports.');
  delete from asset_connections;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from asset_connections.');
  delete from maintenance_logs;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from maintenance_logs.');
  delete from operational_procedures;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from operational_procedures.');
  delete from infrastructure_assets;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from infrastructure_assets.');
  delete from districts;
  dbms_output.put_line('  Deleted ' || sql%rowcount || ' rows from districts.');

  dbms_output.put_line('--- Phase 1: Structural Data ---');

  reset_json;
  append_json(q'~[{"name":"Harbor District","classification":"industrial","population":12400,"area_sq_km":8.7,"description":"Waterfront industrial zone housing the city's primary port facilities, maritime infrastructure, and coastal monitoring systems."},{"name":"Meridian Heights","classification":"residential","population":45200,"area_sq_km":12.3,"description":"Primary residential district with mixed-density housing, neighborhood parks, and distributed utility infrastructure."},{"name":"Ironworks Quarter","classification":"industrial","population":8900,"area_sq_km":6.1,"description":"Heavy industrial zone containing power generation, water treatment, and waste management facilities."},{"name":"Central Commons","classification":"mixed-use","population":31500,"area_sq_km":4.2,"description":"City center with commercial towers, civic buildings, transit hubs, and high-density residential blocks."},{"name":"Greenfield Park","classification":"residential","population":28700,"area_sq_km":15.8,"description":"Suburban residential district with extensive green spaces, underground utility corridors, and distributed solar installations."},{"name":"Riverside Corridor","classification":"commercial","population":19300,"area_sq_km":5.4,"description":"Commercial and light industrial strip along the river, featuring warehousing, logistics facilities, and flood management infrastructure."},{"name":"Northgate Industrial","classification":"industrial","population":5600,"area_sq_km":9.9,"description":"Northern industrial park with chemical processing plants, rail freight terminals, and high-voltage power distribution."}]~');
  insert into districts (
    name, classification, population, area_sq_km,
    center_latitude, center_longitude, boundary, description
  )
  select d.name,
         d.classification,
         d.population,
         d.area_sq_km,
         d.center_latitude,
         d.center_longitude,
         sdo_geometry(
           2003,
           4326,
           null,
           sdo_elem_info_array(1, 1003, 3),
           sdo_ordinate_array(d.min_longitude, d.min_latitude, d.max_longitude, d.max_latitude)
         ),
         d.description
    from (
      select jt.*,
             case jt.name
               when 'Harbor District' then 38.926400
               when 'Meridian Heights' then 38.932600
               when 'Ironworks Quarter' then 38.919900
               when 'Central Commons' then 38.924300
               when 'Greenfield Park' then 38.914900
               when 'Riverside Corridor' then 38.929200
               when 'Northgate Industrial' then 38.937500
             end center_latitude,
             case jt.name
               when 'Harbor District' then -79.851700
               when 'Meridian Heights' then -79.843300
               when 'Ironworks Quarter' then -79.858500
               when 'Central Commons' then -79.846900
               when 'Greenfield Park' then -79.840100
               when 'Riverside Corridor' then -79.836600
               when 'Northgate Industrial' then -79.854400
             end center_longitude,
             case jt.name
               when 'Harbor District' then 38.922800
               when 'Meridian Heights' then 38.929200
               when 'Ironworks Quarter' then 38.916500
               when 'Central Commons' then 38.921200
               when 'Greenfield Park' then 38.911200
               when 'Riverside Corridor' then 38.925600
               when 'Northgate Industrial' then 38.934200
             end min_latitude,
             case jt.name
               when 'Harbor District' then 38.929800
               when 'Meridian Heights' then 38.936000
               when 'Ironworks Quarter' then 38.923300
               when 'Central Commons' then 38.927500
               when 'Greenfield Park' then 38.918700
               when 'Riverside Corridor' then 38.932700
               when 'Northgate Industrial' then 38.941000
             end max_latitude,
             case jt.name
               when 'Harbor District' then -79.856900
               when 'Meridian Heights' then -79.848700
               when 'Ironworks Quarter' then -79.864000
               when 'Central Commons' then -79.851500
               when 'Greenfield Park' then -79.845600
               when 'Riverside Corridor' then -79.841400
               when 'Northgate Industrial' then -79.859900
             end min_longitude,
             case jt.name
               when 'Harbor District' then -79.846300
               when 'Meridian Heights' then -79.838000
               when 'Ironworks Quarter' then -79.853000
               when 'Central Commons' then -79.842200
               when 'Greenfield Park' then -79.834900
               when 'Riverside Corridor' then -79.831700
               when 'Northgate Industrial' then -79.849000
             end max_longitude
        from json_table(l_json, '\$[*]' columns (
          name           varchar2(100)  path '\$.name',
          classification varchar2(50)   path '\$.classification',
          population     number         path '\$.population',
          area_sq_km     number         path '\$.area_sq_km',
          description    varchar2(4000) path '\$.description'
        )) jt
    ) d;
  dbms_output.put_line('  Inserted ' || sql%rowcount || ' districts.');

  reset_json;
  append_json(q'~[{"name":"Harbor Bridge","asset_type":"bridge","criticality":5,"district_name":"Harbor District","status":"active","commissioned_date":"1987-03-15","description":"Primary vehicular and pedestrian bridge spanning the harbor inlet. Four-lane capacity with dedicated pedestrian walkways.","specifications":{"spanLength_m":485,"loadCapacity_t":5000,"laneCount":4,"material":"steel-concrete composite","deckWidth_m":22}}~');
  append_json(q'~,{"name":"Meridian Overpass","asset_type":"bridge","criticality":4,"district_name":"Meridian Heights","status":"active","commissioned_date":"2003-08-22","description":"Grade-separated highway overpass connecting Meridian Heights to Central Commons.","specifications":{"spanLength_m":210,"loadCapacity_t":3500,"laneCount":2,"material":"pre-stressed concrete","clearance_m":5.2}}~');
  append_json(q'~,{"name":"Riverside Pedestrian Bridge","asset_type":"bridge","criticality":3,"district_name":"Riverside Corridor","status":"active","commissioned_date":"2015-06-10","description":"Cable-stayed pedestrian and cyclist bridge crossing the river at Riverside Corridor.","specifications":{"spanLength_m":165,"loadCapacity_t":500,"laneCount":0,"material":"steel cable-stayed","deckWidth_m":4.5}}~');
  append_json(q'~,{"name":"Substation Gamma","asset_type":"substation","criticality":5,"district_name":"Ironworks Quarter","status":"active","commissioned_date":"1995-11-01","description":"Primary high-voltage substation serving Ironworks Quarter and portions of Central Commons.","specifications":{"voltageRating_kv":132,"transformerCount":3,"peakCapacity_mw":250,"coolingType":"ONAN/ONAF"}}~');
  append_json(q'~,{"name":"Substation Delta","asset_type":"substation","criticality":4,"district_name":"Northgate Industrial","status":"active","commissioned_date":"2001-04-18","description":"Distribution substation for Northgate Industrial, handling heavy industrial loads.","specifications":{"voltageRating_kv":66,"transformerCount":2,"peakCapacity_mw":120,"coolingType":"ONAF"}}~');
  append_json(q'~,{"name":"Substation Epsilon","asset_type":"substation","criticality":4,"district_name":"Central Commons","status":"active","commissioned_date":"2010-09-30","description":"Urban distribution substation embedded within Central Commons, serving commercial and residential loads.","specifications":{"voltageRating_kv":33,"transformerCount":4,"peakCapacity_mw":80,"coolingType":"ONAN"}}~');
  append_json(q'~,{"name":"Pipeline North-7","asset_type":"pipeline","criticality":5,"district_name":"Northgate Industrial","status":"active","commissioned_date":"1998-02-14","description":"High-pressure water main running from the northern reservoir through Northgate Industrial to Ironworks Quarter.","specifications":{"diameter_mm":600,"material":"ductile iron","pressureRating_kpa":1200,"length_km":12.4}}~');
  append_json(q'~,{"name":"Pipeline South-3","asset_type":"pipeline","criticality":3,"district_name":"Greenfield Park","status":"active","commissioned_date":"2005-07-20","description":"Medium-pressure distribution main serving Greenfield Park residential areas.","specifications":{"diameter_mm":400,"material":"HDPE","pressureRating_kpa":800,"length_km":8.1}}~');
  append_json(q'~,{"name":"Harbor Outfall Main","asset_type":"pipeline","criticality":4,"district_name":"Harbor District","status":"active","commissioned_date":"1992-12-05","description":"Treated wastewater outfall pipeline extending from the Ironworks treatment plant to the harbor discharge point.","specifications":{"diameter_mm":900,"material":"reinforced concrete","pressureRating_kpa":400,"length_km":3.2}}~');
  append_json(q'~,{"name":"Central Gas Distribution","asset_type":"pipeline","criticality":4,"district_name":"Central Commons","status":"active","commissioned_date":"2008-03-11","description":"Natural gas distribution network serving Central Commons commercial and residential buildings.","specifications":{"diameter_mm":200,"material":"steel","pressureRating_kpa":700,"length_km":6.8}}~');
  append_json(q'~,{"name":"Harbor Bridge Sensor Array A","asset_type":"sensor","criticality":3,"district_name":"Harbor District","status":"active","commissioned_date":"2018-05-14","description":"Structural health monitoring array on Harbor Bridge north pylon. Measures vibration, strain, and temperature.","specifications":{"sensorTypes":["accelerometer","strain gauge","thermocouple"],"sampleRate_hz":100,"channels":24,"powerSource":"solar"}}~');
  append_json(q'~,{"name":"Harbor Bridge Sensor Array B","asset_type":"sensor","criticality":3,"district_name":"Harbor District","status":"active","commissioned_date":"2018-05-14","description":"Structural health monitoring array on Harbor Bridge south pylon and deck midspan.","specifications":{"sensorTypes":["accelerometer","strain gauge","displacement"],"sampleRate_hz":100,"channels":18,"powerSource":"solar"}}~');
  append_json(q'~,{"name":"Flood Gauge Station R1","asset_type":"sensor","criticality":4,"district_name":"Riverside Corridor","status":"active","commissioned_date":"2016-01-20","description":"River level and flow rate monitoring station at the upstream boundary of Riverside Corridor.","specifications":{"sensorTypes":["ultrasonic level","doppler flow","rain gauge"],"sampleRate_hz":1,"channels":6,"powerSource":"mains with battery backup"}}~');
  append_json(q'~,{"name":"Air Quality Monitor NI-01","asset_type":"sensor","criticality":3,"district_name":"Northgate Industrial","status":"active","commissioned_date":"2020-11-08","description":"Continuous air quality monitoring station at the perimeter of Northgate Industrial.","specifications":{"sensorTypes":["PM2.5","PM10","NO2","SO2","O3","CO"],"sampleRate_hz":0.1,"channels":8,"powerSource":"mains"}}~');
  append_json(q'~,{"name":"Seismic Station CC-01","asset_type":"sensor","criticality":4,"district_name":"Central Commons","status":"active","commissioned_date":"2019-07-15","description":"Strong-motion seismic sensor installed at the base of the Central Commons transit hub.","specifications":{"sensorTypes":["triaxial accelerometer"],"sampleRate_hz":200,"channels":3,"powerSource":"mains with UPS"}}~');
  append_json(q'~,{"name":"Comms Tower Alpha","asset_type":"communication_tower","criticality":4,"district_name":"Meridian Heights","status":"active","commissioned_date":"2012-08-30","description":"Primary communications tower for Meridian Heights, hosting cellular, emergency services, and IoT network antennas.","specifications":{"height_m":65,"antennaCount":12,"coverageRadius_km":8,"backhaul":"fiber"}}~');
  append_json(q'~,{"name":"Comms Tower Beta","asset_type":"communication_tower","criticality":4,"district_name":"Northgate Industrial","status":"active","commissioned_date":"2014-03-22","description":"Industrial communications tower serving Northgate Industrial with SCADA telemetry and process control networks.","specifications":{"height_m":45,"antennaCount":8,"coverageRadius_km":5,"backhaul":"fiber + microwave"}}~');
  append_json(q'~,{"name":"Harbor Relay Station","asset_type":"communication_tower","criticality":4,"district_name":"Harbor District","status":"active","commissioned_date":"2017-09-01","description":"Maritime communications relay providing VHF, AIS, and port operations connectivity.","specifications":{"height_m":35,"antennaCount":6,"coverageRadius_km":15,"backhaul":"fiber"}}~');
  append_json(q'~,{"name":"Ironworks Water Treatment Plant","asset_type":"treatment_plant","criticality":5,"district_name":"Ironworks Quarter","status":"active","commissioned_date":"1990-06-15","description":"Municipal wastewater treatment facility processing flows from Central Commons, Meridian Heights, and Ironworks Quarter.","specifications":{"capacity_mld":120,"treatmentLevel":"tertiary","processType":"activated sludge with UV disinfection","sludgeHandling":"anaerobic digestion"}}~');
  append_json(q'~,{"name":"Riverside Pump Station","asset_type":"pump_station","criticality":4,"district_name":"Riverside Corridor","status":"active","commissioned_date":"2007-10-12","description":"Stormwater pump station managing flood risk along the Riverside Corridor.","specifications":{"pumpCount":4,"totalCapacity_ls":2500,"backupPower":"diesel generator","activationTrigger":"river level > 4.2m"}}~');
  append_json(q'~,{"name":"Greenfield Booster Station","asset_type":"pump_station","criticality":4,"district_name":"Greenfield Park","status":"active","commissioned_date":"2009-01-28","description":"Water pressure booster station maintaining supply pressure across the elevated sections of Greenfield Park.","specifications":{"pumpCount":3,"totalCapacity_ls":800,"backupPower":"diesel generator","activationTrigger":"pressure < 350 kPa"}}~');
  append_json(q'~,{"name":"Harbor Seawall Section A","asset_type":"retaining_wall","criticality":4,"district_name":"Harbor District","status":"active","commissioned_date":"1985-04-20","description":"Concrete seawall protecting Harbor District infrastructure from tidal and storm surge events.","specifications":{"length_m":450,"height_m":6.5,"material":"reinforced concrete with steel sheet piling","designWaveHeight_m":3.5}}~');
  append_json(q'~,{"name":"Meridian Cut Retaining Wall","asset_type":"retaining_wall","criticality":4,"district_name":"Meridian Heights","status":"active","commissioned_date":"2003-08-22","description":"Reinforced earth retaining wall along the highway cut for Meridian Overpass approaches.","specifications":{"length_m":280,"height_m":8.0,"material":"mechanically stabilized earth","designLoad_kpa":20}}~');
  append_json(q'~,{"name":"Northern Reservoir","asset_type":"reservoir","criticality":5,"district_name":"Northgate Industrial","status":"active","commissioned_date":"1978-09-10","description":"Primary potable water storage reservoir supplying the northern half of the city via Pipeline North-7.","specifications":{"capacity_ml":85,"depth_m":12,"coverType":"floating cover","treatmentOnsite":false}}~');
	  append_json(q'~,{"name":"Greenfield Solar Array","asset_type":"solar_installation","criticality":3,"district_name":"Greenfield Park","status":"active","commissioned_date":"2021-02-15","description":"Distributed rooftop and ground-mount solar installation across Greenfield Park public buildings.","specifications":{"peakCapacity_kw":2400,"panelCount":6000,"inverterType":"string","annualYield_mwh":3800}}~');
	  append_json(q'~,{"name":"Northgate Freight Terminal","asset_type":"rail_terminal","criticality":4,"district_name":"Northgate Industrial","status":"active","commissioned_date":"1982-11-30","description":"Rail freight terminal handling bulk materials for Northgate Industrial facilities.","specifications":{"trackCount":6,"maxTrainLength_m":800,"craneCapacity_t":50,"annualThroughput_t":2500000}}~');
	  append_json(q'~,{"name":"City Operations Control Center","asset_type":"operations_center","criticality":5,"district_name":"Central Commons","status":"active","commissioned_date":"2016-04-05","description":"Central SCADA and city infrastructure coordination facility used by operators to monitor power, water, bridge, and environmental systems.","specifications":{"operatingSeats":18,"backupPowerHours":72,"scadaSystems":["power grid","water distribution","transportation","environmental monitoring"],"networkZones":6,"incidentRooms":3}}~');
	  append_json(q'~,{"name":"Emergency Operations Center","asset_type":"emergency_operations_center","criticality":5,"district_name":"Central Commons","status":"active","commissioned_date":"2011-09-12","description":"Citywide emergency coordination facility activated during infrastructure incidents, flood events, hazardous releases, and major service disruptions.","specifications":{"dispatchConsoles":24,"backupPowerHours":96,"activationLevel":"citywide","shelterCapacity":120,"satelliteLinks":4}}]~');
	  select count(*)
	    into l_total
	    from json_table(l_json, '\$[*]' columns (
	      name varchar2(200) path '\$.name'
	    ));

	  insert into infrastructure_assets (
	    district_id, name, asset_type, criticality, status,
	    latitude, longitude, location,
    commissioned_date, description, specifications
  )
  select d.district_id,
         a.name,
         a.asset_type,
         a.criticality,
         a.status,
         a.asset_latitude,
         a.asset_longitude,
         sdo_geometry(
           2001,
           4326,
           sdo_point_type(a.asset_longitude, a.asset_latitude, null),
           null,
           null
         ),
         to_date(a.commissioned_date, 'YYYY-MM-DD'),
         a.description,
         json(a.specifications)
    from (
      select jt.*,
             case jt.name
               when 'Harbor Bridge' then 38.925900
               when 'Meridian Overpass' then 38.934000
               when 'Riverside Pedestrian Bridge' then 38.929900
               when 'Substation Gamma' then 38.920600
               when 'Substation Delta' then 38.938200
               when 'Substation Epsilon' then 38.923600
               when 'Pipeline North-7' then 38.936100
               when 'Pipeline South-3' then 38.914500
               when 'Harbor Outfall Main' then 38.924100
               when 'Central Gas Distribution' then 38.922800
               when 'Harbor Bridge Sensor Array A' then 38.926300
               when 'Harbor Bridge Sensor Array B' then 38.925500
               when 'Flood Gauge Station R1' then 38.928600
               when 'Air Quality Monitor NI-01' then 38.937200
               when 'Seismic Station CC-01' then 38.923900
               when 'Comms Tower Alpha' then 38.933200
               when 'Comms Tower Beta' then 38.939000
               when 'Harbor Relay Station' then 38.927000
               when 'Ironworks Water Treatment Plant' then 38.919200
               when 'Riverside Pump Station' then 38.930200
               when 'Greenfield Booster Station' then 38.915800
               when 'Harbor Seawall Section A' then 38.926900
               when 'Meridian Cut Retaining Wall' then 38.932400
               when 'Northern Reservoir' then 38.940300
               when 'Greenfield Solar Array' then 38.913800
               when 'Northgate Freight Terminal' then 38.935500
               when 'City Operations Control Center' then 38.924400
               when 'Emergency Operations Center' then 38.925100
             end asset_latitude,
             case jt.name
               when 'Harbor Bridge' then -79.849800
               when 'Meridian Overpass' then -79.842600
               when 'Riverside Pedestrian Bridge' then -79.835500
               when 'Substation Gamma' then -79.858200
               when 'Substation Delta' then -79.855000
               when 'Substation Epsilon' then -79.846000
               when 'Pipeline North-7' then -79.852500
               when 'Pipeline South-3' then -79.839700
               when 'Harbor Outfall Main' then -79.853100
               when 'Central Gas Distribution' then -79.845400
               when 'Harbor Bridge Sensor Array A' then -79.850500
               when 'Harbor Bridge Sensor Array B' then -79.849100
               when 'Flood Gauge Station R1' then -79.836900
               when 'Air Quality Monitor NI-01' then -79.857300
               when 'Seismic Station CC-01' then -79.845200
               when 'Comms Tower Alpha' then -79.844400
               when 'Comms Tower Beta' then -79.853400
               when 'Harbor Relay Station' then -79.848600
               when 'Ironworks Water Treatment Plant' then -79.856400
               when 'Riverside Pump Station' then -79.834900
               when 'Greenfield Booster Station' then -79.838900
               when 'Harbor Seawall Section A' then -79.852100
               when 'Meridian Cut Retaining Wall' then -79.841500
               when 'Northern Reservoir' then -79.851200
               when 'Greenfield Solar Array' then -79.836800
               when 'Northgate Freight Terminal' then -79.856800
               when 'City Operations Control Center' then -79.846700
               when 'Emergency Operations Center' then -79.845900
             end asset_longitude
        from json_table(l_json, '\$[*]' columns (
          name              varchar2(200)  path '\$.name',
          asset_type        varchar2(100)  path '\$.asset_type',
          criticality       number         path '\$.criticality',
          district_name     varchar2(100)  path '\$.district_name',
          status            varchar2(50)   path '\$.status',
          commissioned_date varchar2(10)   path '\$.commissioned_date',
          description       varchar2(4000) path '\$.description',
          specifications    clob format json path '\$.specifications'
	        )) jt
	    ) a
	    join districts d on d.name = a.district_name;
	  l_inserted := sql%rowcount;
	  dbms_output.put_line('  Inserted ' || l_inserted || ' infrastructure assets.');
	  if l_inserted != l_total then
	    raise_application_error(
	      -20010,
	      'Infrastructure asset seed mismatch: inserted ' || l_inserted ||
	      ' of ' || l_total || ' JSON assets. Check district_name values.'
	    );
	  end if;

	  select count(*)
	    into l_count
	    from infrastructure_assets
	   where latitude is null
	      or longitude is null
	      or location is null;
	  if l_count > 0 then
	    raise_application_error(-20011, 'Infrastructure asset location data missing for ' || l_count || ' asset row(s).');
	  end if;

  reset_json;
  append_json(q'~[{"from_asset_name":"Harbor Bridge Sensor Array A","to_asset_name":"Harbor Bridge","connection_type":"monitors","description":"North pylon structural health monitoring"},{"from_asset_name":"Harbor Bridge Sensor Array B","to_asset_name":"Harbor Bridge","connection_type":"monitors","description":"South pylon and deck midspan monitoring"},{"from_asset_name":"Flood Gauge Station R1","to_asset_name":"Riverside Pump Station","connection_type":"monitors","description":"River level triggers pump activation"},{"from_asset_name":"Air Quality Monitor NI-01","to_asset_name":"Northgate Freight Terminal","connection_type":"monitors","description":"Perimeter air quality monitoring for freight operations"},{"from_asset_name":"Seismic Station CC-01","to_asset_name":"Meridian Overpass","connection_type":"monitors","description":"Strong-motion monitoring for structural assessment"},{"from_asset_name":"Substation Gamma","to_asset_name":"Ironworks Water Treatment Plant","connection_type":"powers","description":"Primary power supply for treatment plant operations"},{"from_asset_name":"Substation Gamma","to_asset_name":"Harbor Bridge","connection_type":"powers","description":"Bridge lighting and sensor power supply"},{"from_asset_name":"Substation Delta","to_asset_name":"Northgate Freight Terminal","connection_type":"powers","description":"Power supply for terminal cranes and facilities"},{"from_asset_name":"Substation Delta","to_asset_name":"Comms Tower Beta","connection_type":"powers","description":"Power supply for industrial communications"},{"from_asset_name":"Substation Epsilon","to_asset_name":"Seismic Station CC-01","connection_type":"powers","description":"Mains power with UPS backup"},{"from_asset_name":"Greenfield Solar Array","to_asset_name":"Greenfield Booster Station","connection_type":"powers","description":"Supplementary solar power for booster pumps"},{"from_asset_name":"Northern Reservoir","to_asset_name":"Pipeline North-7","connection_type":"feeds","description":"Potable water supply from reservoir to distribution"},{"from_asset_name":"Pipeline North-7","to_asset_name":"Ironworks Water Treatment Plant","connection_type":"feeds","description":"Raw water supply to treatment facility"},{"from_asset_name":"Pipeline South-3","to_asset_name":"Greenfield Booster Station","connection_type":"feeds","description":"Distribution main to pressure booster"},{"from_asset_name":"Ironworks Water Treatment Plant","to_asset_name":"Harbor Outfall Main","connection_type":"feeds","description":"Treated effluent discharge to harbor"},{"from_asset_name":"Riverside Pump Station","to_asset_name":"Flood Gauge Station R1","connection_type":"connects-to","description":"Pump station intake at gauge location"},{"from_asset_name":"Comms Tower Alpha","to_asset_name":"Comms Tower Beta","~');
	  append_json(q'~connection_type":"connects-to","description":"Microwave backhaul link between towers"},{"from_asset_name":"Comms Tower Beta","to_asset_name":"Harbor Relay Station","connection_type":"connects-to","description":"Network relay for port operations"},{"from_asset_name":"Comms Tower Alpha","to_asset_name":"Harbor Bridge Sensor Array A","connection_type":"connects-to","description":"IoT data backhaul from bridge sensors"},{"from_asset_name":"Comms Tower Alpha","to_asset_name":"Harbor Bridge Sensor Array B","connection_type":"connects-to","description":"IoT data backhaul from bridge sensors"},{"from_asset_name":"Comms Tower Beta","to_asset_name":"Air Quality Monitor NI-01","connection_type":"connects-to","description":"Telemetry data backhaul"},{"from_asset_name":"Harbor Seawall Section A","to_asset_name":"Harbor Bridge","connection_type":"supports","description":"Seawall protects bridge abutment foundations"},{"from_asset_name":"Meridian Cut Retaining Wall","to_asset_name":"Meridian Overpass","connection_type":"supports","description":"Retaining wall stabilizes overpass approach embankments"},{"from_asset_name":"Central Gas Distribution","to_asset_name":"Substation Epsilon","connection_type":"connects-to","description":"Gas supply for backup generation at substation"},{"from_asset_name":"Pipeline North-7","to_asset_name":"Pipeline South-3","connection_type":"connects-to","description":"Interconnection valve at distribution junction"},{"from_asset_name":"Substation Gamma","to_asset_name":"Substation Epsilon","connection_type":"powers","description":"132kV to 33kV step-down feed via transmission line T4-Central"},{"from_asset_name":"Comms Tower Alpha","to_asset_name":"Seismic Station CC-01","connection_type":"connects-to","description":"Seismic data telemetry backhaul to central monitoring"},{"from_asset_name":"Flood Gauge Station R1","to_asset_name":"Riverside Pedestrian Bridge","connection_type":"monitors","description":"River level monitoring at pedestrian bridge crossing"}~');
	  append_json(q'~,{"from_asset_name":"City Operations Control Center","to_asset_name":"Substation Gamma","connection_type":"monitors","description":"SCADA operators monitor transformer health, relay events, and load transfer risk"},{"from_asset_name":"City Operations Control Center","to_asset_name":"Pipeline North-7","connection_type":"monitors","description":"Operations center receives pressure, valve, and leak telemetry"},{"from_asset_name":"City Operations Control Center","to_asset_name":"Emergency Operations Center","connection_type":"coordinates-with","description":"Operations staff escalate infrastructure incidents to emergency command"},{"from_asset_name":"Emergency Operations Center","to_asset_name":"Harbor Bridge","connection_type":"coordinates","description":"Emergency command coordinates bridge closures and public safety messaging"},{"from_asset_name":"Emergency Operations Center","to_asset_name":"Riverside Pump Station","connection_type":"coordinates","description":"Emergency command coordinates flood pump deployment during storm events"},{"from_asset_name":"Emergency Operations Center","to_asset_name":"Pipeline North-7","connection_type":"coordinates","description":"Emergency command coordinates water main isolation and customer notifications"},{"from_asset_name":"Comms Tower Alpha","to_asset_name":"City Operations Control Center","connection_type":"connects-to","description":"Primary wireless backhaul into the city operations network"}]~');
	  select count(*)
	    into l_total
	    from json_table(l_json, '\$[*]' columns (
	      from_asset_name varchar2(200) path '\$.from_asset_name'
	    ));

	  insert into asset_connections (from_asset_id, to_asset_id, connection_type, description)
	  select from_asset.asset_id,
	         to_asset.asset_id,
         c.connection_type,
         c.description
    from json_table(l_json, '\$[*]' columns (
      from_asset_name varchar2(200)  path '\$.from_asset_name',
      to_asset_name   varchar2(200)  path '\$.to_asset_name',
      connection_type varchar2(100)  path '\$.connection_type',
      description     varchar2(4000) path '\$.description'
	    )) c
	    join infrastructure_assets from_asset on from_asset.name = c.from_asset_name
	    join infrastructure_assets to_asset on to_asset.name = c.to_asset_name;
	  l_inserted := sql%rowcount;
	  dbms_output.put_line('  Inserted ' || l_inserted || ' asset connections.');
	  if l_inserted != l_total then
	    raise_application_error(
	      -20012,
	      'Asset connection seed mismatch: inserted ' || l_inserted ||
	      ' of ' || l_total || ' JSON connections. Check from_asset_name/to_asset_name values.'
	    );
	  end if;

  reset_json;
  append_json(q'~[{"procedureId":"SOP-HV-001","title":"High Voltage Substation Inspection Protocol","category":"electrical","version":"3.2","lastRevised":"2025-11-15","estimatedDuration_min":180,"requiredPersonnel":3,"applicableAssetTypes":["substation"],"safetyChecklist":["Verify all circuits de-energized and locked out","Confirm grounding cables attached at all work points","PPE inspection: arc-flash suit (min CAT 3), insulated gloves (Class 2), face shield","Verify rescue equipment staged and accessible","Confirm communication with control room established"],"equipment":["thermal imaging camera","insulation resistance tester (megger)","partial discharge detector","oil sampling kit","digital multimeter (CAT IV rated)"],"steps":[{"order":1,"action":"Perform visual inspection of all transformer bushings and insulators","notes":"Document any discoloration, cracks, or oil leaks with photos"},{"order":2,"action":"Conduct thermal scan of all bus connections and switchgear","notes":"Flag any connection with temperature differential exceeding 10\u00b0C above ambient"},{"order":3,"action":"Perform insulation resistance testing on each transformer winding","notes":"Minimum acceptable reading: 1 G\u03a9 at 5 kV test voltage"},{"order":4,"action":"Collect oil samples from each transformer for dissolved gas analysis","notes":"Use clean syringes; label with transformer ID and date"},{"order":5,"action":"Inspect cooling systems: fans, radiators, oil pumps","notes":"Run each fan group for 2 minutes and verify operation"},{"order":6,"action":"Check protection relay settings and test trip circuits","notes":"Do not perform live trip tests without control room authorization"},{"order":7,"action":"Inspect earthing system and measure ground resistance","notes":"Maximum acceptable ground resistance: 1 \u03a9"}],"escalation":{"contact":"Grid Operations Center","phone":"555-0142","conditions":["Evidence of active arcing","Transformer oil level below minimum mark","Ground fault detected","Protection relay failure"]}},{"procedureId":"SOP-BR-001","title":"Bridge Structural Assessment Procedure","category":"structural","version":"2.1","lastRevised":"2025-08-20","estimatedDuration_min":240,"requiredPersonnel":4,"applicableAssetTypes":["bridge"],"safetyChecklist":["Traffic management plan approved and signage deployed","Fall protection harnesses inspected and worn by all personnel","Under-bridge inspection platform pre-positioned and load-tested","Marine traffic notified if working over navigable water","Weather check: postpone if wind exceeds 40 km/h or lightning within 10 km"],"equipment":["Schmidt rebound hammer","ultrasonic thickness gauge","crack width comparator cards","half-cell potential meter","drone with high-resolution camera","GPS-enabled measurement tools"],"steps":[{"order":1,"acti~');
  append_json(q'~on":"Conduct drone survey of entire bridge deck and superstructure","notes":"Capture ortho-mosaic imagery at minimum 2 cm/pixel resolution"},{"order":2,"action":"Inspect all expansion joints for debris, damage, and alignment","notes":"Measure joint gap at 3 points per joint and compare to design values"},{"order":3,"action":"Perform concrete condition survey on substructure elements","notes":"Use Schmidt hammer at 10 test points per pier; record rebound numbers"},{"order":4,"action":"Measure crack widths on all visible cracks exceeding 0.1 mm","notes":"Map crack locations on structural drawings; flag any crack > 0.3 mm"},{"order":5,"action":"Conduct ultrasonic thickness measurements on steel elements","notes":"Test at 5 points per member; flag any section loss exceeding 10%"},{"order":6,"action":"Inspect bearing assemblies for corrosion, displacement, and lubrication","notes":"Photograph each bearing; note any lateral displacement > 5 mm"},{"order":7,"action":"Assess drainage system for blockages and erosion damage","notes":"Flush each scupper and downpipe; verify discharge at outfall"},{"order":8,"action":"Review and update sensor calibration records for installed monitoring equipment","notes":"Cross-reference live sensor readings with manual measurements"}],"escalation":{"contact":"Structural Engineering Division","phone":"555-0187","conditions":["Any crack exceeding 1.0 mm width","Section loss exceeding 25%","Bearing displacement exceeding 15 mm","Visible reinforcement corrosion"]}},{"procedureId":"SOP-PL-001","title":"Pressurized Pipeline Integrity Assessment","category":"pipeline","version":"4.0","lastRevised":"2025-10-02","estimatedDuration_min":300,"requiredPersonnel":3,"applicableAssetTypes":["pipeline"],"safetyChecklist":["Pipeline depressurized and isolated at both ends (double block and bleed)","Atmospheric monitoring: confirm no hazardous gases (LEL < 10%, O2 19.5-23.5%)","Confined space entry permit obtained if entering valve chambers","Traffic management in place for any road crossings","Emergency shutdown procedure reviewed with all team members"],"equipment":["inline inspection pig launcher/receiver","magnetic flux leakage (MFL) tool","pipeline CCTV crawler","ultrasonic wall thickness gauge","pressure test pump and chart recorder"],"steps":[{"order":1,"action":"Verify pipeline isolation and depressurization at all boundary valves","notes":"Record valve positions and lock-out/tag-out details"},{"order":2,"action":"Launch CCTV inspection crawler from upstream access point","notes":"Record video with distance counter; note any anomalies with timestamps"},{"order":3,"action":"Perform ultrasonic wall thickness measurements at accessible locations","notes":"Minimum 5 readings per pipe section; focus on bends and joints"},{"order":4,"action"~');
  append_json(q'~:"Inspect all valve chambers for leaks, corrosion, and structural integrity","notes":"Check valve stem packing, flange bolts, and chamber ventilation"},{"order":5,"action":"Conduct hydrostatic pressure test at 1.5x operating pressure","notes":"Hold for minimum 2 hours; acceptable pressure drop: < 0.5%"},{"order":6,"action":"Inspect cathodic protection system: anodes, rectifiers, test stations","notes":"Measure pipe-to-soil potential at each test station; target: -850 mV to -1200 mV (Cu/CuSO4)"},{"order":7,"action":"Survey pipeline route for surface settlement, erosion, or third-party damage","notes":"Walk full route; compare surface levels to baseline survey"}],"escalation":{"contact":"Water Infrastructure Emergency Line","phone":"555-0129","conditions":["Wall thickness below 60% of nominal","Failed hydrostatic test","Active leak detected","Cathodic protection failure across multiple stations"]}},{"procedureId":"SOP-EM-001","title":"Emergency Pipeline Leak Response","category":"emergency","version":"5.1","lastRevised":"2026-01-10","estimatedDuration_min":0,"requiredPersonnel":4,"applicableAssetTypes":["pipeline","pump_station"],"safetyChecklist":["Establish exclusion zone: minimum 25 m radius from leak source","Atmospheric monitoring continuous at exclusion zone boundary","Emergency services notified if gas or hazardous material involved","Downstream consumers notified of potential supply interruption","PPE: waterproof suit, respiratory protection if gas risk, steel-toe boots"],"equipment":["pipe repair clamps (assorted sizes)","portable pump for dewatering","pipe freezing kit","leak sealing compound","portable generator and lighting"],"steps":[{"order":1,"action":"Assess leak severity and classify","notes":"Category 1 (spray/gush) requires immediate isolation"},{"order":2,"action":"Isolate the affected section using upstream and downstream valves","notes":"Coordinate with SCADA control room"},{"order":3,"action":"Establish dewatering and containment at the leak site","notes":"Prevent uncontrolled runoff"},{"order":4,"action":"Apply temporary repair appropriate to pipe material and pressure","notes":"Replace with permanent repair within 72 hours"},{"order":5,"action":"Restore pressure gradually and monitor for 30 minutes","notes":"Increase in 25% increments"},{"order":6,"action":"Document incident with GPS, photos, and cause assessment","notes":"Submit report within 24 hours"}],"escalation":{"contact":"Emergency Operations Center","phone":"555-0911","conditions":["Category 1 leak on main exceeding 300 mm","Any gas leak","Contamination risk to potable supply"]}},{"procedureId":"SOP-CT-001","title":"Communications Tower Routine Maintenance","category":"communications","version":"2.0","lastRevised":"2025-06-18","estimatedDuration_min":150,"requiredPerso~');
  append_json(q'~nnel":2,"applicableAssetTypes":["communication_tower"],"safetyChecklist":["Tower climbing certification verified","Fall arrest system inspected","RF exposure assessment completed","Weather check: no climbing if wind > 50 km/h","Rescue plan in place"],"equipment":["cable analyzer","fiber optic power meter and OTDR","torque wrench set","coaxial connector toolkit","tower-rated tool lanyard system"],"steps":[{"order":1,"action":"Inspect tower structure: legs, bracing, bolted connections, foundation","notes":"Check for corrosion, loose bolts, cracked welds"},{"order":2,"action":"Inspect all antenna mounts, brackets, and alignment","notes":"Verify azimuth and tilt match RF design"},{"order":3,"action":"Test all coaxial and fiber optic cable runs","notes":"Sweep test coax; OTDR test fiber"},{"order":4,"action":"Inspect obstruction lighting","notes":"Replace failed lamps immediately"},{"order":5,"action":"Inspect grounding system","notes":"Maximum 5 ohm for telecom towers"},{"order":6,"action":"Clean and inspect equipment shelter","notes":"Check HVAC, UPS, batteries, fire suppression"}],"escalation":{"contact":"Network Operations Center","phone":"555-0165","conditions":["Structural damage","Obstruction lighting failure","Ground resistance exceeding 10 ohm"]}},{"procedureId":"SOP-WTP-001","title":"Water Treatment Plant Process Audit","category":"water-treatment","version":"3.0","lastRevised":"2025-09-05","estimatedDuration_min":360,"requiredPersonnel":3,"applicableAssetTypes":["treatment_plant"],"safetyChecklist":["Chemical handling PPE available","Safety showers and eyewash tested","Atmospheric monitoring in enclosed areas","Chlorine gas detection verified","Emergency spill kit staged"],"equipment":["portable turbidity meter","pH/ORP meter","dissolved oxygen meter","sample bottles","portable flow meter"],"steps":[{"order":1,"action":"Review SCADA trends for previous 30 days","notes":"Flag any exceedances"},{"order":2,"action":"Inspect primary treatment","notes":"Check scrapers, scum removal, sludge blanket"},{"order":3,"action":"Inspect secondary treatment","notes":"Verify DO setpoints"},{"order":4,"action":"Inspect tertiary treatment and disinfection","notes":"Check UV lamp intensity"},{"order":5,"action":"Audit chemical storage","notes":"Verify inventory"},{"order":6,"action":"Review laboratory QA/QC","notes":"Verify calibration records"},{"order":7,"action":"Inspect sludge handling","notes":"Check digester gas production"},{"order":8,"action":"Review compliance reporting","notes":"Ensure reports submitted on time"}],"escalation":{"contact":"Environmental Compliance Manager","phone":"555-0134","conditions":["Effluent exceeding permit limits","Chemical spill","UV system failure"]}},{"procedureId":"SOP-FLD-001","title":"Flood Event Response and Pump Station ~');
  append_json(q'~Operations","category":"emergency","version":"4.2","lastRevised":"2025-12-01","estimatedDuration_min":0,"requiredPersonnel":3,"applicableAssetTypes":["pump_station","sensor"],"safetyChecklist":["Swift-water rescue team on standby","Exclusion zone around wet well","Backup generator fuel > 75%","Communication with EOC established","Road closure requests submitted"],"equipment":["portable submersible pump","sandbags and flood barriers","portable generator","water level data logger","satellite phone"],"steps":[{"order":1,"action":"Activate flood monitoring protocol","notes":"Begin at river level > 3.5 m"},{"order":2,"action":"Pre-position portable pumps and barriers","notes":"Priority: Riverside underpass, Harbor low points"},{"order":3,"action":"Verify all permanent pump stations operational","notes":"Run each pump for 2 minutes"},{"order":4,"action":"Activate Riverside Pump Station at trigger level","notes":"Confirm SCADA receiving data"},{"order":5,"action":"Deploy field crew to monitor flow paths","notes":"Focus on trash screens and culverts"},{"order":6,"action":"Post-event cleanup and inspection","notes":"Document high-water marks with GPS"}],"escalation":{"contact":"Emergency Operations Center","phone":"555-0911","conditions":["River level exceeding 5.5 m","Pump station failure during event","Road inundation"]}},{"procedureId":"SOP-SW-001","title":"Seawall and Retaining Wall Annual Inspection","category":"structural","version":"1.3","lastRevised":"2025-07-22","estimatedDuration_min":200,"requiredPersonnel":2,"applicableAssetTypes":["retaining_wall"],"safetyChecklist":["Tidal schedule reviewed","Fall protection for crest work","Marine exclusion zone if waterside","Hard hat and high-vis at all times","First aid kit with hypothermia blanket"],"equipment":["crack monitoring pins and caliper","ground-penetrating radar","survey-grade GPS","underwater camera","concrete coring drill"],"steps":[{"order":1,"action":"Survey wall crest and toe levels","notes":"Flag settlement > 15 mm"},{"order":2,"action":"Visual inspection of wall face","notes":"Map all defects on elevation drawings"},{"order":3,"action":"Install or read crack monitoring pins","notes":"Record to 0.05 mm precision"},{"order":4,"action":"Inspect drainage systems","notes":"Blocked weepholes indicate failure"},{"order":5,"action":"Conduct GPR survey along crest","notes":"Focus near stormwater outfalls"},{"order":6,"action":"Inspect toe protection at low tide","notes":"Note scour depth measurements"}],"escalation":{"contact":"Coastal Engineering Division","phone":"555-0176","conditions":["Settlement > 50 mm","Crack growth > 0.5 mm/year","Void detected behind wall"]}},{"procedureId":"SOP-SOL-001","title":"Solar Installation Performance Audit","category":"electrical","version":"1.1","lastRevised":"~');
	  append_json(q'~2025-05-30","estimatedDuration_min":120,"requiredPersonnel":2,"applicableAssetTypes":["solar_installation"],"safetyChecklist":["DC isolation verified","Arc-flash PPE for inverter access","Roof access harness and anchors","No work on wet panels","Fire isolation switches accessible"],"equipment":["IV curve tracer","thermal imaging camera","digital multimeter (CAT III)","irradiance meter","insulation resistance tester"],"steps":[{"order":1,"action":"Review monitoring data vs expected yield","notes":"Flag output < 90% expected"},{"order":2,"action":"Conduct thermal survey of panel strings","notes":"Identify hot spots"},{"order":3,"action":"Perform IV curve tracing on sample strings","notes":"Flag degradation > 2%/year"},{"order":4,"action":"Inspect inverter operation","notes":"Check THD < 5%, PF > 0.95"},{"order":5,"action":"Inspect racking and grounding","notes":"Check for corrosion"},{"order":6,"action":"Clean panels if soiling > 5%","notes":"Deionized water only"}],"escalation":{"contact":"Renewable Energy Operations Manager","phone":"555-0198","conditions":["Inverter failure","DC ground fault","Hot spot > 30C differential"]}}]~');
	  select count(*)
	    into l_total
	    from json_table(l_json, '\$[*]' columns (
	      procedure_id varchar2(50) path '\$.procedureId'
	    ));

	  insert into operational_procedures (data)
	  select json(p.data)
	    from json_table(l_json, '\$[*]' columns (
	      data clob format json path '\$'
	    )) p;
	  l_inserted := sql%rowcount;
	  dbms_output.put_line('  Inserted ' || l_inserted || ' operational procedures.');
	  if l_inserted != l_total then
	    raise_application_error(
	      -20013,
	      'Operational procedure seed mismatch: inserted ' || l_inserted ||
	      ' of ' || l_total || ' JSON procedures.'
	    );
	  end if;

  dbms_output.put_line('--- Phase 2: Generated Content Files ---');

  l_json := load_json_file('maintenance_logs.json');
  select count(*)
    into l_total
    from json_table(l_json, '\$[*]' columns (
      asset_name varchar2(200) path '\$.asset_name'
    ));

  insert into maintenance_logs (asset_id, log_date, severity, narrative)
  select a.asset_id,
         sysdate - nvl(m.days_ago, 1),
         m.severity,
         m.narrative
    from json_table(l_json, '\$[*]' columns (
      asset_name varchar2(200)  path '\$.asset_name',
      severity   varchar2(20)   path '\$.severity',
      narrative  varchar2(4000) path '\$.narrative',
      days_ago   number         path '\$.days_ago'
    )) m
    join infrastructure_assets a on a.name = m.asset_name;
	  l_inserted := sql%rowcount;
	  dbms_output.put_line('  Inserted ' || l_inserted || ' maintenance logs.');
	  if l_total - l_inserted > 0 then
	    dbms_output.put_line('  Skipped ' || (l_total - l_inserted) || ' maintenance logs with unknown assets.');
	    raise_application_error(
	      -20014,
	      'Maintenance log seed mismatch: inserted ' || l_inserted ||
	      ' of ' || l_total || ' generated maintenance logs. Check asset_name values.'
	    );
	  end if;
  dbms_lob.freetemporary(l_json);

  insert into maintenance_logs (asset_id, log_date, severity, narrative)
  select a.asset_id,
         sysdate - s.days_ago,
         s.severity,
         s.narrative
    from (
      select 'Substation Gamma' asset_name,
             'critical' severity,
             q'~SCADA correlation drill: Substation Gamma transformer T2 reported relay chatter, cooling fan failure, and rising oil temperature during peak load. The City Operations Control Center correlated the event with voltage sag alarms feeding Harbor Bridge lighting, Ironworks Water Treatment Plant pumps, and Substation Epsilon. Operators transferred load, opened an emergency work order, and notified the Emergency Operations Center for cascading outage monitoring.~' narrative,
             1 days_ago
        from dual
      union all
      select 'City Operations Control Center',
             'warning',
             q'~Control room operators observed repeated SCADA alarm bursts tied to Substation Gamma T2 protective relay instability. Event timeline review showed 11 relay chatter events in 18 minutes, one failed cooling fan telemetry channel, and elevated load transfer risk to Central Commons feeders. Operators created a root-cause incident package and linked it to Substation Gamma for follow-up analysis.~',
             1
        from dual
      union all
      select 'Emergency Operations Center',
             'warning',
             q'~Emergency Operations Center opened a coordination watch for potential cascading outage from Substation Gamma. Staff prepared public notification templates for Harbor Bridge traffic controls, water treatment continuity plans, and backup dispatch coverage. No citywide activation was required, but the watch remains tied to Substation Gamma until relay testing and cooling repairs are complete.~',
             1
        from dual
    ) s
    join infrastructure_assets a on a.name = s.asset_name;
  dbms_output.put_line('  Inserted ' || sql%rowcount || ' scenario maintenance logs.');

  l_json := load_json_file('inspection_reports.json');
  l_inserted := 0;
  l_findings := 0;
  l_skipped := 0;

  for r in (
    select jt.asset_name,
           jt.inspector,
           jt.overall_grade,
           jt.summary,
           jt.days_ago,
           jt.findings
      from json_table(l_json, '\$[*]' columns (
        asset_name    varchar2(200)  path '\$.asset_name',
        inspector     varchar2(200)  path '\$.inspector',
        overall_grade varchar2(10)   path '\$.overall_grade',
        summary       varchar2(4000) path '\$.summary',
        days_ago      number         path '\$.days_ago',
        findings      clob format json path '\$.findings'
      )) jt
  ) loop
    begin
      select asset_id
        into l_asset_id
        from infrastructure_assets
       where name = r.asset_name
       fetch first 1 row only;
    exception
      when no_data_found then
        l_skipped := l_skipped + 1;
        dbms_output.put_line('  Skipping report for unknown asset: ' || r.asset_name);
        continue;
    end;

    insert into inspection_reports (asset_id, inspector, inspect_date, overall_grade, summary)
    values (l_asset_id, r.inspector, sysdate - nvl(r.days_ago, 1), r.overall_grade, r.summary)
    returning report_id into l_report_id;
    l_inserted := l_inserted + 1;

    insert into inspection_findings (report_id, category, severity, description, recommendation)
    select l_report_id,
           f.category,
           f.severity,
           f.description,
           f.recommendation
      from json_table(r.findings, '\$[*]' columns (
        category       varchar2(100)  path '\$.category',
        severity       varchar2(20)   path '\$.severity',
        description    varchar2(4000) path '\$.description',
        recommendation varchar2(4000) path '\$.recommendation'
      )) f;
    l_findings := l_findings + sql%rowcount;
  end loop;

  select asset_id
    into l_asset_id
    from infrastructure_assets
   where name = 'Substation Gamma';

  insert into inspection_reports (asset_id, inspector, inspect_date, overall_grade, summary)
  values (
    l_asset_id,
    'Riley Chen',
    sysdate - 1,
    'D',
    'Scenario inspection: Substation Gamma has an active reliability concern centered on transformer T2 relay instability, degraded cooling fan performance, and downstream load transfer risk. Findings connect directly to City Operations Control Center alarms and Emergency Operations Center watch status. Immediate relay testing, fan replacement, and load-transfer validation are required before returning the asset to normal risk posture.'
  )
  returning report_id into l_report_id;
  l_inserted := l_inserted + 1;

  insert into inspection_findings (report_id, category, severity, description, recommendation)
  select l_report_id,
         f.category,
         f.severity,
         f.description,
         f.recommendation
    from (
      select 'electrical protection' category,
             'critical' severity,
             'Protective relay on transformer T2 produced repeated chatter events during a controlled load-transfer test. Event recorder confirms unstable trip logic under peak load conditions and correlates with SCADA voltage sag alarms.' description,
             'Remove T2 from automatic transfer service, perform relay bench testing, validate protection settings, and require control center sign-off before restoring normal operations.' recommendation
        from dual
      union all
      select 'cooling system',
             'critical',
             'Cooling fan assembly Fan-AX-1200 failed to sustain rated airflow and transformer oil temperature rose toward alarm threshold during the same event window.',
             'Replace the failed fan assembly, dynamically balance the cooling bank, and monitor oil temperature under staged load for at least two operating cycles.'
        from dual
      union all
      select 'operational coordination',
             'warning',
             'City Operations Control Center and Emergency Operations Center procedures were followed, but incident notes used inconsistent asset tags for downstream Harbor Bridge and water-treatment dependencies.',
             'Standardize incident tags for connected assets and attach the graph dependency list to future Substation Gamma escalation packages.'
        from dual
    ) f;
  l_findings := l_findings + sql%rowcount;

	  dbms_output.put_line('  Inserted ' || l_inserted || ' inspection reports.');
	  dbms_output.put_line('  Inserted ' || l_findings || ' inspection findings.');
	  if l_skipped > 0 then
	    dbms_output.put_line('  Skipped ' || l_skipped || ' inspection reports with unknown assets.');
	    raise_application_error(
	      -20015,
	      'Inspection report seed mismatch: skipped ' || l_skipped ||
	      ' generated inspection report(s). Check asset_name values.'
	    );
	  end if;
  dbms_lob.freetemporary(l_json);

  commit;

  dbms_output.put_line('--- Summary ---');
  for t in (
    select 'districts' table_name from dual union all
    select 'infrastructure_assets' from dual union all
    select 'operational_procedures' from dual union all
    select 'maintenance_logs' from dual union all
    select 'inspection_reports' from dual union all
    select 'inspection_findings' from dual union all
    select 'asset_connections' from dual
  ) loop
    execute immediate 'select count(*) from ' || t.table_name into l_count;
    dbms_output.put_line('  ' || rpad(t.table_name, 30) || lpad(l_count, 6) || ' rows');
  end loop;

    if l_json is not null and dbms_lob.istemporary(l_json) = 1 then
      dbms_lob.freetemporary(l_json);
    end if;

    insert into prism_build_log (step_name, status, detail)
    values (
      '35-load-prism-initial-data',
      'SUCCESS',
      'Loaded PRISM seed data, including Elkins WV spatial coordinates.'
    );
    commit;

    dbms_output.put_line('Seed data loading complete.');
  exception
    when others then
      l_error_detail := substr(sqlerrm, 1, 4000);
      rollback;
      begin
        insert into prism_build_log (step_name, status, detail)
        values ('35-load-prism-initial-data', 'FAILURE', l_error_detail);
        commit;
      exception
        when others then
          null;
      end;
      if dbms_lob.fileisopen(l_file) = 1 then
        dbms_lob.fileclose(l_file);
    end if;
    if l_json is not null and dbms_lob.istemporary(l_json) = 1 then
      dbms_lob.freetemporary(l_json);
    end if;
    raise;
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  Seed data loading complete."
echo "  Next step: run 40-generate-embeddings.sh to vectorize content."
echo "========================================================================"
