-- Zorg ervoor dat de database alleen wordt aangemaakt als deze niet bestaat
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'withdb') THEN
        CREATE DATABASE withdb WITH TEMPLATE template0 ENCODING 'UTF8' LOCALE 'en_US.utf8';
    END IF;
END $$;

-- Wissel van database (Docker-vriendelijk alternatief voor \connect)
\c withdb;

-- Zet de eigenaar correct
ALTER DATABASE withdb OWNER TO admin;

-- Maak tabellen aan als ze niet bestaan
CREATE TABLE IF NOT EXISTS public.document_files (
    id SERIAL PRIMARY KEY,
    set_id INTEGER REFERENCES public.document_sets(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.document_sets (
    id SERIAL PRIMARY KEY,
    identifier INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    status VARCHAR(50) DEFAULT 'new',
    processed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.questions (
    id SERIAL PRIMARY KEY,
    shortdesc VARCHAR(64) UNIQUE NOT NULL,
    template TEXT,
    prefill VARCHAR(128)
);

-- Functies en triggers opnieuw toevoegen als ze niet bestaan
CREATE OR REPLACE FUNCTION public.check_pending_sets() RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    next_set_id INT;
BEGIN
    SELECT id INTO next_set_id FROM document_sets
    WHERE status = 'new'
    ORDER BY id ASC
    LIMIT 1;

    IF next_set_id IS NOT NULL THEN
        PERFORM pg_notify('new_set', next_set_id::text);
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_new_set() RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    in_processing_count INT;
BEGIN
    SELECT COUNT(*) INTO in_processing_count FROM document_sets WHERE status = 'processing';

    IF in_processing_count = 0 THEN
        PERFORM pg_notify('new_set', NEW.id::text);
    END IF;

    RETURN NEW;
END;
$$;

-- Triggers opnieuw aanmaken
DROP TRIGGER IF EXISTS new_set_trigger ON public.document_sets;
CREATE TRIGGER new_set_trigger AFTER INSERT ON public.document_sets FOR EACH ROW EXECUTE FUNCTION public.notify_new_set();

DROP TRIGGER IF EXISTS process_next_set_trigger ON public.document_sets;
CREATE TRIGGER process_next_set_trigger AFTER UPDATE ON public.document_sets
FOR EACH ROW WHEN ((OLD.status = 'processing') AND (NEW.status = 'finished'))
EXECUTE FUNCTION public.check_pending_sets();
