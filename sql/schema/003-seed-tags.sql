-- Seed data: Initial taxonomy for transcript classification
-- Maps categories to Obsidian vault folder structure

-- Infrastructure parent tags
INSERT INTO tags (name, category, parent_tag_id, obsidian_folder)
VALUES
    ('infrastructure', 'infra', NULL, 'infrastructure'),
    ('study', 'study', NULL, 'study'),
    ('backup', 'backup', NULL, 'backup'),
    ('gpu', 'gpu', NULL, 'gpu'),
    ('kubernetes', 'kubernetes', NULL, 'kubernetes');

-- Infrastructure subtags (parent: infrastructure)
INSERT INTO tags (name, category, parent_tag_id, obsidian_folder)
VALUES
    ('hardware', 'infra', (SELECT id FROM tags WHERE name = 'infrastructure'), 'infrastructure/hardware'),
    ('network', 'infra', (SELECT id FROM tags WHERE name = 'infrastructure'), 'infrastructure/network'),
    ('storage', 'infra', (SELECT id FROM tags WHERE name = 'infrastructure'), 'infrastructure/storage');

-- Study/certification subtags (parent: study)
INSERT INTO tags (name, category, parent_tag_id, obsidian_folder)
VALUES
    ('kcna', 'study', (SELECT id FROM tags WHERE name = 'study'), 'study/kcna'),
    ('az104', 'study', (SELECT id FROM tags WHERE name = 'study'), 'study/az104');

-- Backup subtags (parent: backup)
INSERT INTO tags (name, category, parent_tag_id, obsidian_folder)
VALUES
    ('architecture', 'backup', (SELECT id FROM tags WHERE name = 'backup'), 'backup/architecture');

-- GPU subtags (parent: gpu)
INSERT INTO tags (name, category, parent_tag_id, obsidian_folder)
VALUES
    ('optimization', 'gpu', (SELECT id FROM tags WHERE name = 'gpu'), 'gpu/optimization');

-- Kubernetes subtags (parent: kubernetes)
INSERT INTO tags (name, category, parent_tag_id, obsidian_folder)
VALUES
    ('troubleshooting', 'kubernetes', (SELECT id FROM tags WHERE name = 'kubernetes'), 'kubernetes/troubleshooting');

-- Verify insertion
SELECT
    t1.id AS tag_id,
    t1.name AS tag_name,
    t1.category,
    t2.name AS parent_name,
    t1.obsidian_folder
FROM tags t1
LEFT JOIN tags t2 ON t1.parent_tag_id = t2.id
ORDER BY t1.category, t1.id;
