-- ============================================================================
-- MFGPulse AI: 19 Notifications
-- Email + in-app notification infrastructure with admin-configurable settings
-- ============================================================================

USE DATABASE MFGPULSE_DB;

-- ============================================================================
-- 1. NOTIFICATION_SETTINGS — admin-configurable per event type
-- ============================================================================
CREATE TABLE IF NOT EXISTS RAW_IT.NOTIFICATION_SETTINGS (
    EVENT_TYPE VARCHAR(30) NOT NULL PRIMARY KEY,
    EVENT_LABEL VARCHAR(100),
    EMAIL_ENABLED BOOLEAN DEFAULT FALSE,
    IN_APP_ENABLED BOOLEAN DEFAULT TRUE,
    EMAIL_RECIPIENTS VARCHAR(500) DEFAULT '',
    NOTIFY_PERSONAS VARCHAR(200) DEFAULT 'PLANT_MANAGER,APP_ADMIN',
    PRIORITY VARCHAR(10) DEFAULT 'NORMAL',
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY VARCHAR(100) DEFAULT CURRENT_USER()
);

-- Seed: 7 event types with sensible defaults
MERGE INTO RAW_IT.NOTIFICATION_SETTINGS t
USING (
    SELECT * FROM VALUES
        ('WO_CREATED',   'Work order created',    FALSE, TRUE, '', 'SHIFT_SUPERVISOR,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('WO_STARTED',   'Work order started',    FALSE, TRUE, '', 'SHIFT_SUPERVISOR,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('WO_COMPLETED', 'Work order completed',  FALSE, TRUE, '', 'SHIFT_SUPERVISOR,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('PO_CREATED',   'Purchase order created', FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('PO_APPROVED',  'Purchase order approved',FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('PO_REJECTED',  'Purchase order rejected',FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'HIGH'),
        ('PO_RECEIVED',  'Purchase order received',FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'NORMAL')
    AS s(EVENT_TYPE, EVENT_LABEL, EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY)
) s ON t.EVENT_TYPE = s.EVENT_TYPE
WHEN NOT MATCHED THEN INSERT (EVENT_TYPE, EVENT_LABEL, EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY)
    VALUES (s.EVENT_TYPE, s.EVENT_LABEL, s.EMAIL_ENABLED, s.IN_APP_ENABLED, s.EMAIL_RECIPIENTS, s.NOTIFY_PERSONAS, s.PRIORITY);

-- ============================================================================
-- 2. APP_NOTIFICATIONS — in-app notification store
-- ============================================================================
CREATE TABLE IF NOT EXISTS RAW_IT.APP_NOTIFICATIONS (
    NOTIF_ID VARCHAR(200) NOT NULL PRIMARY KEY,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EVENT_TYPE VARCHAR(50) NOT NULL,
    PERSONA_TARGET VARCHAR(50),
    TITLE VARCHAR(500),
    MESSAGE VARCHAR(2000),
    ENTITY_ID VARCHAR(100),
    PRIORITY VARCHAR(20) DEFAULT 'NORMAL',
    IS_READ BOOLEAN DEFAULT FALSE,
    DISMISSED BOOLEAN DEFAULT FALSE
);

-- ============================================================================
-- 3. EMAIL NOTIFICATION INTEGRATION
-- ============================================================================
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS MFGPULSE_EMAIL
    TYPE = EMAIL
    ENABLED = TRUE;

-- ============================================================================
-- 4. SEND_MFGPULSE_EMAIL — wrapper for SYSTEM$SEND_SNOWFLAKE_NOTIFICATION
-- ============================================================================
CREATE OR REPLACE PROCEDURE RAW_IT.SEND_MFGPULSE_EMAIL(
    P_SUBJECT VARCHAR, P_BODY_HTML VARCHAR, P_RECIPIENTS VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    IF (:p_recipients IS NULL OR LENGTH(TRIM(:p_recipients)) = 0) THEN
        RETURN ''SKIPPED: No recipients'';
    END IF;
    BEGIN
        CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
            SNOWFLAKE.NOTIFICATION.TEXT_HTML(:p_body_html),
            SNOWFLAKE.NOTIFICATION.EMAIL_INTEGRATION_CONFIG(
                ''MFGPULSE_EMAIL'',
                :p_subject,
                SPLIT(:p_recipients, '','')
            )
        );
        RETURN ''SENT'';
    EXCEPTION
        WHEN OTHER THEN RETURN ''EMAIL_ERROR: '' || SQLERRM;
    END;
END;
';

-- ============================================================================
-- 5. LOG_APP_NOTIFICATION — central notification dispatcher
-- ============================================================================
CREATE OR REPLACE PROCEDURE RAW_IT.LOG_APP_NOTIFICATION(
    P_EVENT_TYPE VARCHAR, P_TITLE VARCHAR, P_MESSAGE VARCHAR, P_ENTITY_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_email_enabled BOOLEAN DEFAULT FALSE;
    v_in_app_enabled BOOLEAN DEFAULT TRUE;
    v_recipients VARCHAR DEFAULT '''';
    v_personas VARCHAR DEFAULT '''';
    v_priority VARCHAR DEFAULT ''NORMAL'';
    v_notif_count NUMBER DEFAULT 0;
    v_email_result VARCHAR DEFAULT ''SKIPPED'';
BEGIN
    -- Read settings for this event type
    BEGIN
        SELECT EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY
        INTO :v_email_enabled, :v_in_app_enabled, :v_recipients, :v_personas, :v_priority
        FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS
        WHERE EVENT_TYPE = :p_event_type;
    EXCEPTION
        WHEN OTHER THEN
            v_in_app_enabled := TRUE;
            v_personas := ''PLANT_MANAGER,APP_ADMIN'';
    END;

    -- In-app notifications: one per target persona
    IF (:v_in_app_enabled) THEN
        INSERT INTO MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
            (NOTIF_ID, EVENT_TYPE, PERSONA_TARGET, TITLE, MESSAGE, ENTITY_ID, PRIORITY)
        SELECT
            :p_event_type || ''-'' || value || ''-'' || TO_CHAR(CURRENT_TIMESTAMP(), ''YYYYMMDD_HH24MISS''),
            :p_event_type,
            TRIM(value),
            :p_title,
            :p_message,
            :p_entity_id,
            :v_priority
        FROM TABLE(SPLIT_TO_TABLE(:v_personas, '',''));

        SELECT COUNT(*) INTO :v_notif_count
        FROM MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
        WHERE ENTITY_ID = :p_entity_id AND EVENT_TYPE = :p_event_type;
    END IF;

    -- Email notification
    IF (:v_email_enabled AND LENGTH(TRIM(:v_recipients)) > 0) THEN
        LET email_subject VARCHAR := ''MFGPulse '' || :v_priority || '': '' || :p_title;
        LET email_body VARCHAR := ''<div style="font-family:sans-serif;"><h3>'' || :p_title || ''</h3><p>'' || :p_message || ''</p><p style="color:#666;font-size:12px;">Entity: '' || COALESCE(:p_entity_id, ''N/A'') || '' | '' || CURRENT_TIMESTAMP()::VARCHAR || ''</p></div>'';
        CALL MFGPULSE_DB.RAW_IT.SEND_MFGPULSE_EMAIL(:email_subject, :email_body, :v_recipients);
        SELECT * INTO :v_email_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    END IF;

    RETURN OBJECT_CONSTRUCT(
        ''status'', ''OK'',
        ''event_type'', :p_event_type,
        ''in_app_sent'', :v_notif_count,
        ''email_result'', :v_email_result
    );
END;
';
