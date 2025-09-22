SELECT * FROM `fhir-synthea-data.fhir_curated.practitioners` LIMIT 1000;
SELECT * FROM `fhir-synthea-data.fhir_curated.practitioner_roles` LIMIT 1000;
SELECT * FROM `fhir-synthea-data.fhir_curated.observations` LIMIT 1000;
SELECT * FROM `fhir-synthea-data.fhir_curated.conditions` LIMIT 1000;

--Generates create statement for tables created with gui
SELECT 
  CONCAT(
    'CREATE TABLE `', table_schema, '.', table_name, '` (\n',
    STRING_AGG(
      CONCAT('  ', column_name, ' ', data_type,
        CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END
      ), ',\n'
    ),
    '\n);'
  ) AS create_table_sql
FROM `fhir_curated.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'patients'
GROUP BY table_schema, table_name;

CREATE TABLE fhir_curated.practitioner_roles (
    practitioner_role_id STRING NOT NULL,  -- FHIR PractitionerRole id
    practitioner_id STRING NOT NULL,
    organization_id STRING,
    specialty_code STRING,                  -- optional
    specialty_text STRING,                  -- optional
    role_code STRING,                       -- optional
    role_text STRING,                       -- optional
    load_timestamp TIMESTAMP NOT NULL,
    --PRIMARY KEY(practitioner_role_id)
) ;

-- Optional: cluster on practitioner_id for faster queries
-- CLUSTER BY practitioner_id

CREATE TABLE `fhir_curated.patients` (
  patient_id STRING NOT NULL,
  first_name STRING,
  last_name STRING,
  birth_date DATE,
  gender STRING,
  load_timestamp TIMESTAMP NOT NULL
);

CREATE TABLE fhir_curated.conditions (
    condition_id STRING NOT NULL,  -- FHIR Condition id
    patient_id STRING NOT NULL,
    encounter_id STRING NOT NULL,
    clinical_status STRING, 

    -- flattened main code for joins/filtering
    code STRING,                    -- optional (LOINC, SNOMED, etc.)
    code_text STRING,             -- optional
    code_system STRING,                  --optional show system

    --nested array for full fidelity
    codings ARRAY<STRUCT<
      system STRING,
      code STRING,
      display STRING
    >>,

    -- flattened main code for joins/filtering
    category_code STRING,
    category STRING,                -- optional

 --nested array for full fidelity
    category_codings ARRAY<STRUCT<
      system STRING,
      code STRING,
      display STRING
    >>,

    onset_date TIMESTAMP,           -- using TIMESTAMP in case time is relevant
    load_timestamp TIMESTAMP NOT NULL,
    --PRIMARY KEY(condition_id)
) PARTITION BY DATE (load_timestamp)
CLUSTER BY patient_id;

-- Optional: cluster on patient_id for analytics
-- CLUSTER BY patient_id


CREATE TABLE fhir_curated.observations (
    observation_id STRING NOT NULL,       -- FHIR Observation id
    status STRING,
    
    -- flattened main code for joins/filtering
    obs_code STRING,                      -- e.g. LOINC code "718-7"
    system STRING,                        -- system URL "http://loinc.org"
    obs_code_text STRING,                 -- display text "Hemoglobin [Mass/volume] in Blood"

    -- nested array for full fidelity
    codings ARRAY<STRUCT<
        system STRING,
        code STRING,
        display STRING
    >>,

    value_numeric FLOAT64,
    value_text STRING,
    unit STRING,

    -- for capturing codings inside valueCodeableConcept
    value_codings ARRAY<STRUCT<
        system STRING,
        code STRING,
        display STRING
    >>,

    patient_id STRING NOT NULL,
    encounter_id STRING NOT NULL,
    effective_datetime TIMESTAMP,         -- when measurement taken
    load_timestamp TIMESTAMP NOT NULL
)
PARTITION BY DATE(load_timestamp)
CLUSTER BY patient_id, encounter_id;


CREATE TABLE fhir_curated.diagnostic_reports (
    diagnostic_report_id STRING NOT NULL,   -- FHIR DiagnosticReport.id
    patient_id STRING NOT NULL,
    encounter_id STRING,
    status STRING,                          -- e.g., final, amended
    category_code STRING,                   -- e.g., LAB, RADIOLOGY
    category_text STRING,
    code STRING,                            -- report type (LOINC)
    code_text STRING,
    issued TIMESTAMP,                       -- when report was issued
    load_timestamp TIMESTAMP NOT NULL
) PARTITION BY (diagnostic_report_id)
CLUSTER BY patient_id;

CREATE TABLE fhir_curated.diagnostic_report_observations (
    diagnostic_report_id STRING NOT NULL,
    observation_id STRING NOT NULL,
    load_timestamp TIMESTAMP NOT NULL
)CLUSTER BY diagnostic_report_id, patient_id;

-- Optional: cluster by patient_id for faster patient-level queries
-- CLUSTER BY patient_id

CREATE TABLE fhir_curated.claims (
  claim_id STRING NOT NULL,
  use STRING,
  status STRING,
  patient_id STRING,
  claim_type_info STRING,

  -- amounts
  total_value FLOAT64,
  total_currency STRING,

  -- dates
  billable_start TIMESTAMP, 
  billable_end TIMESTAMP,
  created TIMESTAMP,

  -- claim-level provider & facility
  billing_provider STRUCT<
    provider_id STRING,     -- reference to Practitioner/Organization
    provider_type STRING,   -- e.g., "institutional", "professional"
    provider_code STRING    -- NPI, TIN, etc.
  >,
  claim_facility STRUCT<
    facility_id STRING,     -- reference to Location resource
    system STRING,
    code STRING,
    display STRING          -- facility name
  >,

  -- all insurances
  all_insurances ARRAY<STRUCT<
    sequence INT64,
    focal BOOLEAN,
    coverage STRING
  >>,

  -- diagnoses at claim level (optional to keep)
  diagnoses ARRAY<STRUCT<
    diagnosis_id STRING,    -- reference to Condition or normalized ID
    sequence STRING,
    system STRING,          -- ICD-10, SNOMED, etc.
    code STRING,
    display STRING
  >>,

  -- items (each claim line)
  items ARRAY<STRUCT<
    sequence INT64,                       -- line number
    item_type STRING,                     -- productOrService, category, location, encounter
    system STRING,
    code STRING,
    display STRING,
    service_start TIMESTAMP,
    service_end TIMESTAMP,
    net_value FLOAT64,
    net_currency STRING,
    location STRUCT<
      facility_id STRING,
      system STRING,
      code STRING,
      display STRING
    >,
    encounter STRING,

    -- flattened diagnosis/procedure links
    --diagnoses ARRAY<STRUCT<
    --  system STRING,
    --  code STRING,
    --  display STRING
    -->>,
    --procedures ARRAY<STRUCT<
    --  system STRING,
    --  code STRING,
    --  display STRING
    -->>,
    item_text STRING
  >>,

  load_timestamp TIMESTAMP NOT NULL
)
PARTITION BY DATE(billable_start)
CLUSTER BY patient_id, load_timestamp;


--careteam for each encounter
CREATE TABLE fhir_curated.care_teams (
    care_team_id STRING NOT NULL,
    patient_id STRING,
    encounter_id STRING,
    period_start TIMESTAMP,
    period_end TIMESTAMP,
    managing_organization_id STRING,
    load_timestamp TIMESTAMP NOT NULL
)CLUSTER BY patient_id, encounter_id;

--care team for claim
CREATE TABLE fhir_curated.care_team_participants (
    care_team_id STRING NOT NULL,
    member_reference_id STRING NOT NULL,  -- practitioner or organization
    role_code STRING,
    role_text STRING,
    claim_date DATE,
    load_timestamp TIMESTAMP NOT NULL
) PARTITION BY claim_date
CLUSTER BY care_team_id, member_reference_id;

CREATE TABLE fhir_curated.procedures (
    procedure_id STRING NOT NULL,                    -- FHIR Procedure.id
    status STRING,                                   -- procedure status (e.g., completed)
    code STRING,                                     -- SNOMED or other procedure code
    code_text STRING,                                -- human-readable procedure description
    patient_id STRING NOT NULL,                      -- reference to patient
    encounter_id STRING,                             -- reference to encounter
    performer_practitioner_id STRING,               -- optional performer practitioner
    performer_org_id STRING,                         -- optional performer organization
    location_id STRING,                              -- optional location reference
    location_name STRING,                            -- optional human-readable location
    reason_code STRING,                              -- optional reason for procedure
    reason_reference STRING,                         -- optional reference for reason
    body_site STRING,                                -- optional body site
    outcome STRING,                                  -- optional outcome
    follow_up STRING,                                -- optional follow-up
    complication STRING,                             -- optional complications
    performed_start TIMESTAMP,                        -- start timestamp
    performed_end TIMESTAMP,                          -- end timestamp
    load_timestamp TIMESTAMP NOT NULL                -- when data was loaded
)
PARTITION BY DATE(performed_start)                  -- partition by procedure date
CLUSTER BY patient_id, procedure_id;               -- cluster for common query patterns

CREATE TABLE fhir_curated.devices (
    device_id STRING NOT NULL,                 -- FHIR Device.id
    status STRING,                             -- active, inactive, entered-in-error
    distinct_identifier STRING,                -- e.g., UDI or other unique identifier
    manufacture_date DATE,                     -- optional
    expiration_date DATE,                      -- optional
    lot_number STRING,                          -- optional
    serial_number STRING,                       -- optional
    patient_ref STRING,                         -- reference to Patient (optional)
    organization_ref STRING,                    -- reference to Organization (optional)
    device_names ARRAY<STRING>,                 -- human-readable names
    codings ARRAY<STRUCT<
        system STRING,
        code STRING,
        display STRING
    >>,                                         -- array of standard codings (SNOMED, LOINC, etc.)
    resource JSON,                              -- optional: store raw JSON
    load_timestamp TIMESTAMP NOT NULL           -- track when row was ingested
)
PARTITION BY DATE(load_timestamp)               -- incremental ETL, query by ingestion date
CLUSTER BY device_id, patient_ref;             -- improves joins and filter performance

CREATE TABLE fhir_curated.medication_requests (
    medrequest_id STRING NOT NULL,           -- FHIR MedicationRequest id
    status STRING,                           -- active, completed, etc.
    intent STRING,                           -- order, plan, proposal
    medication_id STRING,                     -- reference to Medication table
    subject_patient_id STRING NOT NULL,       -- patient reference
    encounter_id STRING,                      -- encounter reference
    requester_practitioner_id STRING,         -- ordering practitioner
    requester_org_id STRING,                  -- organization placing request
    authored_on TIMESTAMP,                    -- date/time of request
    dosage_instruction ARRAY<STRUCT<         -- nested dosage instructions
        text STRING,
        timing STRUCT<repeat_interval STRING, frequency INT64>,
        route STRING,
        dose_quantity STRUCT<value FLOAT64, unit STRING>
    >>,
    dispense_request STRUCT<                  -- nested dispense details
        quantity STRUCT<value FLOAT64, unit STRING>,
        expected_supply_duration STRUCT<value FLOAT64, unit STRING>,
        number_of_refills INT64
    >,
    resource JSON,                            -- optional: store raw JSON
    load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(authored_on)
CLUSTER BY subject_patient_id, medrequest_id;

CREATE TABLE fhir_curated.medications (
    medication_id STRING NOT NULL,         -- FHIR Medication id
    status STRING,                         -- active, inactive, etc.
    code STRING,                           -- coding system code (RxNorm)
    code_system STRING,                     -- coding system URI
    code_display STRING,                     -- human-readable display
    text STRING,                            -- code text
    resource JSON,                          -- optional: full raw JSON
    load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(load_timestamp)
CLUSTER BY medication_id;

CREATE TABLE fhir_curated.medication_administration (
    medadmin_id STRING NOT NULL,
    status STRING,
    medication_code STRING,
    medication_system STRING,
    medication_display STRING,
    medication_text STRING,
    patient_id STRING NOT NULL,
    encounter_id STRING,
    effective_datetime TIMESTAMP,
    reason_code STRING,
    reason_text STRING,
    resource JSON,
    load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(load_timestamp)
CLUSTER BY medadmin_id, patient_id;






