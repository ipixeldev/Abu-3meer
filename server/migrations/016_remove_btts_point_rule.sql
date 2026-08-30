-- Both Teams To Score is no longer part of the Abu 3meer prediction product.
-- Keep historic prediction/ledger columns intact for audit compatibility, but
-- remove the configurable rule so it cannot be advertised or awarded again.
DELETE FROM point_rules WHERE key = 'bothTeamsScore';
