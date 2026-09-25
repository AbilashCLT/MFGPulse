-- ============================================================================
-- MFGPulse AI: 15 Procurement Tables
-- Suppliers, part-supplier mappings, reservations, purchase orders + seed data
-- ============================================================================

USE DATABASE MFGPULSE_DB;

-- Tables created in 02_base_tables.sql: SUPPLIERS, PART_SUPPLIERS, PART_RESERVATIONS, PURCHASE_ORDERS, PURCHASE_ORDER_LINES

-- Seed: 5 suppliers
INSERT INTO RAW_IT.SUPPLIERS (SUPPLIER_ID, SUPPLIER_NAME, CONTACT_EMAIL, PHONE) VALUES
    ('SUP-001', 'Industrial Parts Co', 'orders@indparts.com', '+1-555-0101'),
    ('SUP-002', 'Atlas Copco Parts Direct', 'parts@atlascopco.com', '+1-555-0102'),
    ('SUP-003', 'Bearing World Inc', 'sales@bearingworld.com', '+1-555-0103'),
    ('SUP-004', 'ThermalTech Supply', 'orders@thermaltech.com', '+1-555-0104'),
    ('SUP-005', 'PumpParts Global', 'sales@pumpparts.com', '+1-555-0105');

-- Seed: 16 part-supplier mappings (preferred suppliers + alternates)
INSERT INTO RAW_IT.PART_SUPPLIERS (PART_ID, SUPPLIER_ID, SUPPLIER_PART_NUMBER, STANDARD_LEAD_TIME_DAYS, EXPEDITE_LEAD_TIME_DAYS, MIN_ORDER_QTY, UNIT_COST, PREFERRED_SUPPLIER) VALUES
    ('PART-001', 'SUP-003', 'BW-6205-2RS', 5, 2, 1, 45, TRUE),
    ('PART-001', 'SUP-001', 'IP-BRG-6205', 7, 3, 2, 42, FALSE),
    ('PART-002', 'SUP-003', 'BW-6308-ZZ', 7, 3, 1, 120, TRUE),
    ('PART-003', 'SUP-001', 'IP-SEAL-V100', 3, 1, 5, 15, TRUE),
    ('PART-004', 'SUP-002', 'AC-FLT-OIL-M', 2, 1, 10, 8, TRUE),
    ('PART-005', 'SUP-001', 'IP-BLT-V100', 4, 2, 3, 25, TRUE),
    ('PART-006', 'SUP-005', 'PP-IMP-CF150', 14, 7, 1, 850, TRUE),
    ('PART-007', 'SUP-005', 'PP-SEAL-MECH', 10, 5, 1, 320, TRUE),
    ('PART-008', 'SUP-001', 'IP-BRG-NUP310', 6, 3, 1, 95, TRUE),
    ('PART-009', 'SUP-004', 'TT-HTR-COIL-3K', 12, 6, 1, 280, TRUE),
    ('PART-010', 'SUP-001', 'IP-COUP-FLEX', 5, 2, 1, 180, TRUE),
    ('PART-011', 'SUP-003', 'BW-6310-2RS', 7, 3, 1, 150, TRUE),
    ('PART-012', 'SUP-001', 'IP-GEAR-SET-G1', 21, 10, 1, 1200, TRUE),
    ('PART-013', 'SUP-001', 'IP-ROLL-CONV', 3, 1, 4, 65, TRUE),
    ('PART-014', 'SUP-002', 'AC-SHAFT-SLV', 12, 5, 1, 450, TRUE),
    ('PART-015', 'SUP-004', 'TT-BLADE-STM', 28, 14, 1, 2200, TRUE);
