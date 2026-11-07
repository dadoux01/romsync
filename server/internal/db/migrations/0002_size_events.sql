-- Trace of the size rules (docs/SPEC.md, "Taille réelle"):
--   trimmed: the upload was cut to the chip size, size_event_from = received size
--   shrunk:  the chip size was reduced to this version's size, size_event_from = previous chip size
--   forced:  the size was forced from the web interface, size_event_from = previous chip size
ALTER TABLE save_versions ADD COLUMN size_event TEXT CHECK (size_event IN ('trimmed', 'shrunk', 'forced'));
ALTER TABLE save_versions ADD COLUMN size_event_from INTEGER;
