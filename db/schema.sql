-- Multi-competition football league management database
-- PostgreSQL 15+
-- Generated schema foundation; review business rules before production migration.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------- Enumerations ----------
CREATE TYPE season_status AS ENUM ('planned','active','completed','archived');
CREATE TYPE competition_format AS ENUM ('single_round_robin','double_round_robin','custom');
CREATE TYPE registration_status AS ENUM ('pending','active','withdrawn','suspended');
CREATE TYPE match_status AS ENUM ('scheduled','postponed','cancelled','completed');
CREATE TYPE result_outcome AS ENUM ('played','abandoned','walkover');
CREATE TYPE matchweek_status AS ENUM ('draft','scheduled','in_progress','completed','locked');
CREATE TYPE movement_type AS ENUM ('promotion','relegation','transfer','reassignment');
CREATE TYPE movement_status AS ENUM ('proposed','approved','rejected','cancelled');
CREATE TYPE user_status AS ENUM ('active','disabled');
CREATE TYPE generation_run_status AS ENUM ('started','completed','failed','abandoned');

-- ---------- Geography ----------
CREATE TABLE countries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    iso_code CHAR(2) UNIQUE
);

CREATE TABLE counties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_id UUID NOT NULL REFERENCES countries(id),
    name TEXT NOT NULL,
    UNIQUE(country_id, name)
);

CREATE TABLE regions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE
);

CREATE TABLE region_counties (
    region_id UUID NOT NULL REFERENCES regions(id) ON DELETE RESTRICT,
    county_id UUID NOT NULL REFERENCES counties(id) ON DELETE RESTRICT,
    PRIMARY KEY(region_id, county_id)
);

-- ---------- Season and competition taxonomy ----------
CREATE TABLE seasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    start_date DATE,
    end_date DATE,
    status season_status NOT NULL DEFAULT 'planned',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE TABLE divisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    level_order INTEGER,
    description TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE zones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    region_id UUID REFERENCES regions(id) ON DELETE RESTRICT,
    UNIQUE(region_id, code)
);

CREATE TABLE competition_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    season_id UUID NOT NULL REFERENCES seasons(id) ON DELETE RESTRICT,
    division_id UUID NOT NULL REFERENCES divisions(id) ON DELETE RESTRICT,
    region_id UUID REFERENCES regions(id) ON DELETE RESTRICT,
    zone_id UUID REFERENCES zones(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    format competition_format NOT NULL DEFAULT 'double_round_robin',
    points_for_win SMALLINT NOT NULL DEFAULT 3 CHECK (points_for_win >= 0),
    points_for_draw SMALLINT NOT NULL DEFAULT 1 CHECK (points_for_draw >= 0),
    points_for_loss SMALLINT NOT NULL DEFAULT 0 CHECK (points_for_loss >= 0),
    walkover_goals SMALLINT NOT NULL DEFAULT 2 CHECK (walkover_goals >= 0),
    expected_team_count SMALLINT CHECK (expected_team_count IS NULL OR expected_team_count >= 2),
    planned_matchweeks SMALLINT CHECK (planned_matchweeks IS NULL OR planned_matchweeks > 0),
    status TEXT NOT NULL DEFAULT 'setup'
        CHECK (status IN ('setup','registration','active','completed','archived')),
    fixture_generation_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(season_id, slug),
    UNIQUE(id, season_id)
);

-- ---------- Teams and registrations ----------
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    short_name TEXT,
    slug TEXT NOT NULL UNIQUE,
    county_id UUID REFERENCES counties(id) ON DELETE SET NULL,
    home_venue TEXT,
    logo_url TEXT,
    founded_year SMALLINT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE team_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_group_id UUID NOT NULL REFERENCES competition_groups(id) ON DELETE RESTRICT,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE RESTRICT,
    registration_status registration_status NOT NULL DEFAULT 'pending',
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    withdrawn_at TIMESTAMPTZ,
    UNIQUE(competition_group_id, team_id),
    UNIQUE(id, competition_group_id)
);

-- ---------- Matchweeks, venues and fixtures ----------
CREATE TABLE venues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    county_id UUID REFERENCES counties(id) ON DELETE SET NULL,
    address TEXT,
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6)
);

CREATE TABLE fixture_generation_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_group_id UUID NOT NULL REFERENCES competition_groups(id) ON DELETE RESTRICT,
    seed TEXT NOT NULL,
    algorithm_version TEXT NOT NULL,
    status generation_run_status NOT NULL DEFAULT 'started',
    idempotency_key TEXT,
    requested_by UUID,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    notes TEXT,
    UNIQUE(competition_group_id, id),
    UNIQUE(competition_group_id, idempotency_key),
    CHECK (
      (status = 'completed' AND completed_at IS NOT NULL)
      OR (status <> 'completed')
    )
);

CREATE UNIQUE INDEX fixture_generation_runs_one_completed
    ON fixture_generation_runs(competition_group_id)
    WHERE status = 'completed';

CREATE UNIQUE INDEX fixture_generation_runs_one_in_flight
    ON fixture_generation_runs(competition_group_id)
    WHERE status = 'started';

CREATE TABLE matchweeks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_group_id UUID NOT NULL REFERENCES competition_groups(id) ON DELETE RESTRICT,
    week_number SMALLINT NOT NULL CHECK (week_number > 0),
    start_date DATE,
    end_date DATE,
    status matchweek_status NOT NULL DEFAULT 'draft',
    generation_run_id UUID REFERENCES fixture_generation_runs(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(competition_group_id, week_number),
    CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date),
    UNIQUE(id, competition_group_id)
);

CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_group_id UUID NOT NULL,
    matchweek_id UUID NOT NULL,
    home_registration_id UUID NOT NULL REFERENCES team_registrations(id) ON DELETE RESTRICT,
    away_registration_id UUID NOT NULL REFERENCES team_registrations(id) ON DELETE RESTRICT,
    scheduled_at TIMESTAMPTZ,
    venue_id UUID REFERENCES venues(id) ON DELETE SET NULL,
    leg_number SMALLINT NOT NULL DEFAULT 1 CHECK (leg_number IN (1,2)),
    reverse_of_match_id UUID REFERENCES matches(id) ON DELETE RESTRICT,
    generation_run_id UUID REFERENCES fixture_generation_runs(id) ON DELETE RESTRICT,
    status match_status NOT NULL DEFAULT 'scheduled',
    current_result_version_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
      (status = 'completed' AND current_result_version_id IS NOT NULL)
      OR (status <> 'completed')
    ),
    CHECK (home_registration_id <> away_registration_id),
    UNIQUE(matchweek_id, home_registration_id, away_registration_id),
    UNIQUE(id, matchweek_id),
    UNIQUE(id, competition_group_id),
    FOREIGN KEY (matchweek_id, competition_group_id)
        REFERENCES matchweeks(id, competition_group_id) ON DELETE RESTRICT
);

CREATE INDEX matches_matchweek_idx ON matches(matchweek_id);
CREATE INDEX matches_scheduled_at_idx ON matches(scheduled_at);
CREATE INDEX matches_home_registration_idx ON matches(home_registration_id);
CREATE INDEX matches_away_registration_idx ON matches(away_registration_id);
CREATE INDEX matches_competition_group_idx ON matches(competition_group_id);
CREATE INDEX matches_generation_run_idx ON matches(generation_run_id);

CREATE UNIQUE INDEX matches_reverse_unique
    ON matches(reverse_of_match_id)
    WHERE reverse_of_match_id IS NOT NULL;

CREATE FUNCTION validate_match_registrations() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    group_id UUID;
    home_group UUID;
    away_group UUID;
BEGIN
    SELECT competition_group_id INTO group_id FROM matchweeks WHERE id = NEW.matchweek_id;
    SELECT competition_group_id INTO home_group FROM team_registrations WHERE id = NEW.home_registration_id;
    SELECT competition_group_id INTO away_group FROM team_registrations WHERE id = NEW.away_registration_id;
    IF group_id IS NULL OR home_group IS DISTINCT FROM group_id OR away_group IS DISTINCT FROM group_id THEN
        RAISE EXCEPTION 'Both teams must be registered in the matchweek competition';
    END IF;
    IF NEW.competition_group_id IS DISTINCT FROM group_id THEN
        RAISE EXCEPTION 'matches.competition_group_id must match matchweek competition_group_id';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER matches_validate_registrations
BEFORE INSERT OR UPDATE OF matchweek_id, home_registration_id, away_registration_id, competition_group_id
ON matches FOR EACH ROW EXECUTE FUNCTION validate_match_registrations();

CREATE FUNCTION validate_match_reverse() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    other matches%ROWTYPE;
BEGIN
    IF NEW.reverse_of_match_id IS NULL THEN
        IF NEW.leg_number = 2 THEN
            RAISE EXCEPTION 'Leg 2 match must reference its leg 1 counterpart';
        END IF;
        RETURN NEW;
    END IF;

    SELECT * INTO other FROM matches WHERE id = NEW.reverse_of_match_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'reverse_of_match_id % does not exist', NEW.reverse_of_match_id;
    END IF;
    IF other.id = NEW.id THEN
        RAISE EXCEPTION 'A match cannot reverse itself';
    END IF;
    IF other.leg_number <> 1 OR NEW.leg_number <> 2 THEN
        RAISE EXCEPTION 'reverse_of_match_id must point from leg 2 to leg 1';
    END IF;
    IF other.competition_group_id <> NEW.competition_group_id THEN
        RAISE EXCEPTION 'Reversed matches must be in the same competition group';
    END IF;
    IF other.home_registration_id <> NEW.away_registration_id
       OR other.away_registration_id <> NEW.home_registration_id THEN
        RAISE EXCEPTION 'Leg 2 home/away must be the reverse of leg 1';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER matches_validate_reverse
BEFORE INSERT OR UPDATE OF reverse_of_match_id, leg_number, home_registration_id, away_registration_id, competition_group_id
ON matches FOR EACH ROW EXECUTE FUNCTION validate_match_reverse();

-- ---------- Immutable result history ----------
CREATE TABLE match_result_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE RESTRICT,
    version_number INTEGER NOT NULL CHECK (version_number > 0),
    outcome result_outcome NOT NULL,
    home_score SMALLINT,
    away_score SMALLINT,
    awarded_registration_id UUID REFERENCES team_registrations(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL,
    notes TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    supersedes_version_id UUID REFERENCES match_result_versions(id) ON DELETE RESTRICT,
    UNIQUE(match_id, version_number),
    UNIQUE(id, match_id),
    CHECK (
      (outcome = 'played' AND home_score IS NOT NULL AND away_score IS NOT NULL
        AND home_score >= 0 AND away_score >= 0 AND awarded_registration_id IS NULL)
      OR
      (outcome = 'walkover' AND home_score IS NOT NULL AND away_score IS NOT NULL
        AND home_score >= 0 AND away_score >= 0 AND awarded_registration_id IS NOT NULL)
      OR
      (outcome = 'abandoned' AND home_score IS NULL AND away_score IS NULL
        AND awarded_registration_id IS NULL)
    )
);

ALTER TABLE matches
ADD CONSTRAINT matches_current_result_fk
FOREIGN KEY (current_result_version_id, id)
REFERENCES match_result_versions(id, match_id)
DEFERRABLE INITIALLY DEFERRED;

CREATE FUNCTION prevent_result_version_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Result versions are immutable; insert a new version instead';
END $$;

CREATE TRIGGER result_versions_immutable
BEFORE UPDATE OR DELETE ON match_result_versions
FOR EACH ROW EXECUTE FUNCTION prevent_result_version_mutation();

CREATE FUNCTION validate_result_version() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    home_id UUID;
    away_id UUID;
    required_goals INTEGER;
BEGIN
    SELECT home_registration_id, away_registration_id
      INTO home_id, away_id FROM matches WHERE id = NEW.match_id;

    IF NEW.outcome = 'walkover' THEN
        IF NEW.awarded_registration_id NOT IN (home_id, away_id) THEN
            RAISE EXCEPTION 'Walkover winner must be one of the match teams';
        END IF;
        SELECT cg.walkover_goals INTO required_goals
        FROM matches m
        JOIN matchweeks mw ON mw.id = m.matchweek_id
        JOIN competition_groups cg ON cg.id = mw.competition_group_id
        WHERE m.id = NEW.match_id;

        IF NEW.awarded_registration_id = home_id THEN
            IF NEW.home_score <> required_goals OR NEW.away_score <> 0 THEN
                RAISE EXCEPTION 'Walkover score must be %-% for the awarded home team', required_goals, 0;
            END IF;
        ELSE
            IF NEW.home_score <> 0 OR NEW.away_score <> required_goals THEN
                RAISE EXCEPTION 'Walkover score must be 0-% for the awarded away team', required_goals;
            END IF;
        END IF;
    END IF;

    IF NEW.version_number > 1 AND NEW.supersedes_version_id IS NULL THEN
        RAISE EXCEPTION 'A subsequent result version must identify the version it supersedes';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER result_versions_validate
BEFORE INSERT ON match_result_versions
FOR EACH ROW EXECUTE FUNCTION validate_result_version();

CREATE FUNCTION validate_match_result_pointer() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.current_result_version_id IS NOT NULL AND NEW.status <> 'completed' THEN
        RAISE EXCEPTION 'A match with a current result must have status = completed';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER matches_validate_result_pointer
BEFORE INSERT OR UPDATE OF current_result_version_id, status
ON matches FOR EACH ROW EXECUTE FUNCTION validate_match_result_pointer();

-- ---------- Users, roles and audit ----------
CREATE TABLE admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    status user_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE match_result_versions
ADD CONSTRAINT result_versions_created_by_fk
FOREIGN KEY (created_by) REFERENCES admin_users(id) ON DELETE SET NULL;

ALTER TABLE fixture_generation_runs
ADD CONSTRAINT fixture_generation_runs_requested_by_fk
FOREIGN KEY (requested_by) REFERENCES admin_users(id) ON DELETE SET NULL;

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    competition_group_id UUID REFERENCES competition_groups(id) ON DELETE CASCADE,
    PRIMARY KEY(user_id, role_id, competition_group_id)
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    action TEXT NOT NULL,
    old_values JSONB,
    new_values JSONB,
    reason TEXT,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX audit_logs_entity_idx ON audit_logs(entity_type, entity_id, created_at DESC);
CREATE INDEX audit_logs_created_at_idx ON audit_logs(created_at DESC);

CREATE FUNCTION prevent_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Audit logs are append-only';
END $$;

CREATE TRIGGER audit_logs_immutable
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

-- ---------- Standings snapshots ----------
CREATE TABLE standings_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_group_id UUID NOT NULL,
    matchweek_id UUID NOT NULL,
    team_registration_id UUID NOT NULL,
    played INTEGER NOT NULL DEFAULT 0,
    won INTEGER NOT NULL DEFAULT 0,
    drawn INTEGER NOT NULL DEFAULT 0,
    lost INTEGER NOT NULL DEFAULT 0,
    goals_for INTEGER NOT NULL DEFAULT 0,
    goals_against INTEGER NOT NULL DEFAULT 0,
    goal_difference INTEGER NOT NULL DEFAULT 0,
    points INTEGER NOT NULL DEFAULT 0,
    position INTEGER NOT NULL CHECK (position > 0),
    calculation_version INTEGER NOT NULL DEFAULT 1,
    points_for_win_snapshot SMALLINT NOT NULL,
    points_for_draw_snapshot SMALLINT NOT NULL,
    points_for_loss_snapshot SMALLINT NOT NULL,
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(matchweek_id, team_registration_id, calculation_version),
    CHECK (played = won + drawn + lost),
    CHECK (goal_difference = goals_for - goals_against),
    FOREIGN KEY (matchweek_id, competition_group_id)
        REFERENCES matchweeks(id, competition_group_id) ON DELETE RESTRICT,
    FOREIGN KEY (team_registration_id, competition_group_id)
        REFERENCES team_registrations(id, competition_group_id) ON DELETE RESTRICT
);

CREATE INDEX standings_lookup_idx
ON standings_snapshots(competition_group_id, matchweek_id, position);
CREATE INDEX standings_latest_idx
ON standings_snapshots(competition_group_id, matchweek_id, team_registration_id, calculation_version DESC);

-- ---------- Promotion / relegation ----------
CREATE TABLE team_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE RESTRICT,
    from_registration_id UUID REFERENCES team_registrations(id) ON DELETE RESTRICT,
    to_competition_group_id UUID NOT NULL REFERENCES competition_groups(id) ON DELETE RESTRICT,
    movement_type movement_type NOT NULL,
    status movement_status NOT NULL DEFAULT 'proposed',
    proposed_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    proposed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at TIMESTAMPTZ,
    decision_reason TEXT,
    notes TEXT,
    resulting_registration_id UUID REFERENCES team_registrations(id) ON DELETE SET NULL,
    CHECK (from_registration_id IS NULL OR from_registration_id <> to_competition_group_id),
    CHECK (
      (status = 'approved' AND approved_by IS NOT NULL AND decided_at IS NOT NULL)
      OR (status <> 'approved')
    )
);

CREATE INDEX team_movements_status_idx ON team_movements(status, proposed_at DESC);

-- ---------- Editorial content ----------
CREATE TABLE articles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    body TEXT,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','review','published','archived')),
    author_id UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE article_competitions (
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    competition_group_id UUID NOT NULL REFERENCES competition_groups(id) ON DELETE CASCADE,
    PRIMARY KEY(article_id, competition_group_id)
);

CREATE TABLE article_matches (
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    PRIMARY KEY(article_id, match_id)
);

-- ---------- Fixture generation function ----------
CREATE OR REPLACE FUNCTION seed_fixture_generation(
    p_competition_group_id UUID,
    p_requested_by          UUID,
    p_seed                  TEXT DEFAULT 'seed',
    p_algorithm_version     TEXT DEFAULT 'rr-circle-v1',
    p_idempotency_key       TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE
    v_run_id        UUID;
    v_existing_run  UUID;
    v_group_status  TEXT;
    v_rounds        INTEGER;
    v_mw_id         UUID;
    v_round         INTEGER;
    v_leg1_ids      UUID[];
    v_leg1_home     UUID[];
    v_leg1_away     UUID[];
    v_reg_ids       UUID[];
    v_n             INTEGER;
    v_expected      INTEGER;
    v_actual        INTEGER;
    v_i             INTEGER;
    v_tmp           UUID;
BEGIN
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existing_run
          FROM fixture_generation_runs
         WHERE competition_group_id = p_competition_group_id
           AND idempotency_key = p_idempotency_key;
        IF v_existing_run IS NOT NULL THEN
            RETURN v_existing_run;
        END IF;
    END IF;

    PERFORM 1 FROM competition_groups
     WHERE id = p_competition_group_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'competition_group % not found', p_competition_group_id;
    END IF;

    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existing_run
          FROM fixture_generation_runs
         WHERE competition_group_id = p_competition_group_id
           AND idempotency_key = p_idempotency_key;
        IF v_existing_run IS NOT NULL THEN
            RETURN v_existing_run;
        END IF;
    END IF;

    SELECT status INTO v_group_status
      FROM competition_groups WHERE id = p_competition_group_id;

    IF v_group_status NOT IN ('registration','active') THEN
        RAISE EXCEPTION 'cannot generate fixtures for group in status %', v_group_status;
    END IF;

    SELECT array_agg(tr.id ORDER BY t.name)
      INTO v_reg_ids
      FROM team_registrations tr
      JOIN teams t ON t.id = tr.team_id
     WHERE tr.competition_group_id = p_competition_group_id
       AND tr.registration_status = 'active';

    v_n := coalesce(array_length(v_reg_ids, 1), 0);
    IF v_n < 2 THEN
        RAISE EXCEPTION 'need at least 2 active registrations, got %', v_n;
    END IF;

    IF v_n % 2 = 1 THEN
        v_reg_ids := v_reg_ids || NULL::UUID;
        v_n := v_n + 1;
    END IF;

    v_rounds := v_n - 1;
    v_expected := (v_n / 2) * (2 * v_rounds) * 2;

    UPDATE fixture_generation_runs
       SET status = 'abandoned', completed_at = now()
     WHERE competition_group_id = p_competition_group_id
       AND status = 'completed';

    INSERT INTO fixture_generation_runs
        (competition_group_id, seed, algorithm_version, status,
         requested_by, idempotency_key)
    VALUES
        (p_competition_group_id, p_seed, p_algorithm_version, 'started',
         p_requested_by, p_idempotency_key)
    RETURNING id INTO v_run_id;

    INSERT INTO audit_logs
        (admin_user_id, entity_type, entity_id, action, new_values, reason)
    VALUES
        (p_requested_by, 'fixture_generation_run', v_run_id, 'started',
         jsonb_build_object(
             'competition_group_id', p_competition_group_id,
             'seed', p_seed,
             'algorithm_version', p_algorithm_version,
             'idempotency_key', p_idempotency_key
         ),
         'Fixture generation started');

    FOR v_round IN 1 .. (2 * v_rounds) LOOP
        INSERT INTO matchweeks
            (competition_group_id, week_number, status, generation_run_id)
        VALUES
            (p_competition_group_id, v_round, 'draft', v_run_id);
    END LOOP;

    v_leg1_ids  := ARRAY[]::UUID[];
    v_leg1_home := ARRAY[]::UUID[];
    v_leg1_away := ARRAY[]::UUID[];

    FOR v_round IN 1 .. v_rounds LOOP
        SELECT id INTO v_mw_id
          FROM matchweeks
         WHERE competition_group_id = p_competition_group_id
           AND week_number = v_round;

        FOR v_i IN 1 .. (v_n / 2) LOOP
            DECLARE
                v_home UUID := v_reg_ids[v_i];
                v_away UUID := v_reg_ids[v_n + 1 - v_i];
                v_match_id UUID;
            BEGIN
                CONTINUE WHEN v_home IS NULL OR v_away IS NULL;

                INSERT INTO matches
                    (competition_group_id, matchweek_id,
                     home_registration_id, away_registration_id,
                     leg_number, generation_run_id)
                VALUES
                    (p_competition_group_id, v_mw_id,
                     v_home, v_away,
                     1, v_run_id)
                RETURNING id INTO v_match_id;

                v_leg1_ids  := v_leg1_ids  || v_match_id;
                v_leg1_home := v_leg1_home || v_home;
                v_leg1_away := v_leg1_away || v_away;
            END;
        END LOOP;

        v_tmp := v_reg_ids[v_n];
        FOR v_i IN REVERSE v_n .. 3 LOOP
            v_reg_ids[v_i] := v_reg_ids[v_i - 1];
        END LOOP;
        v_reg_ids[2] := v_tmp;
    END LOOP;

    FOR v_i IN 1 .. array_length(v_leg1_ids, 1) LOOP
        DECLARE
            v_leg1_id   UUID := v_leg1_ids[v_i];
            v_leg1_wk   INTEGER;
            v_leg2_wk   UUID;
        BEGIN
            SELECT mw.week_number INTO v_leg1_wk
              FROM matches m
              JOIN matchweeks mw ON mw.id = m.matchweek_id
             WHERE m.id = v_leg1_id;

            SELECT id INTO v_leg2_wk
              FROM matchweeks
             WHERE competition_group_id = p_competition_group_id
               AND week_number = v_leg1_wk + v_rounds;

            INSERT INTO matches
                (competition_group_id, matchweek_id,
                 home_registration_id, away_registration_id,
                 leg_number, reverse_of_match_id, generation_run_id)
            VALUES
                (p_competition_group_id, v_leg2_wk,
                 v_leg1_away[v_i], v_leg1_home[v_i],
                 2, v_leg1_id, v_run_id);
        END;
    END LOOP;

    SELECT count(*) INTO v_actual
      FROM matches
     WHERE generation_run_id = v_run_id;

    IF v_actual <> v_expected THEN
        RAISE EXCEPTION
            'fixture generation produced % matches, expected %',
            v_actual, v_expected;
    END IF;

    SELECT count(*) INTO v_actual
      FROM matches m2
     WHERE m2.generation_run_id = v_run_id
       AND m2.leg_number = 2
       AND NOT EXISTS (
           SELECT 1 FROM matches m1
            WHERE m1.id = m2.reverse_of_match_id
              AND m1.generation_run_id = v_run_id
              AND m1.leg_number = 1
       );
    IF v_actual <> 0 THEN
        RAISE EXCEPTION '% leg-2 matches do not reference a leg-1 match in this run', v_actual;
    END IF;

    SELECT count(*) INTO v_actual
      FROM matches m1
     WHERE m1.generation_run_id = v_run_id
       AND m1.leg_number = 1
       AND (SELECT count(*) FROM matches m2
             WHERE m2.reverse_of_match_id = m1.id) <> 1;
    IF v_actual <> 0 THEN
        RAISE EXCEPTION '% leg-1 matches are not reversed exactly once', v_actual;
    END IF;

    SELECT count(*) INTO v_actual
      FROM team_registrations tr
     WHERE tr.competition_group_id = p_competition_group_id
       AND tr.registration_status = 'active'
       AND (SELECT count(*) FROM matches m
             WHERE m.generation_run_id = v_run_id
               AND (m.home_registration_id = tr.id OR m.away_registration_id = tr.id))
           <> (2 * v_rounds);
    IF v_actual <> 0 THEN
        RAISE EXCEPTION '% registrations have the wrong match count', v_actual;
    END IF;

    UPDATE fixture_generation_runs
       SET status = 'completed', completed_at = now()
     WHERE id = v_run_id;

    UPDATE competition_groups
       SET fixture_generation_completed_at = now()
     WHERE id = p_competition_group_id;

    INSERT INTO audit_logs
        (admin_user_id, entity_type, entity_id, action, new_values, reason)
    VALUES
        (p_requested_by, 'fixture_generation_run', v_run_id, 'completed',
         jsonb_build_object(
             'match_count', v_expected,
             'rounds', 2 * v_rounds
         ),
         'Fixture generation completed');

    RETURN v_run_id;
END $$;

-- ---------- Standings recalculation function ----------
CREATE OR REPLACE FUNCTION recalculate_standings(
    p_matchweek_id      UUID,
    p_admin_user_id     UUID DEFAULT NULL
) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_group_id      UUID;
    v_week_number   SMALLINT;
    v_week_status   matchweek_status;
    v_new_version   INTEGER;
    v_row_count     INTEGER;
    v_admin         UUID := p_admin_user_id;
BEGIN
    SELECT mw.competition_group_id, mw.week_number, mw.status
      INTO v_group_id, v_week_number, v_week_status
      FROM matchweeks mw
     WHERE mw.id = p_matchweek_id;

    IF v_group_id IS NULL THEN
        RAISE EXCEPTION 'matchweek % not found', p_matchweek_id;
    END IF;

    IF v_week_status NOT IN ('completed', 'locked') THEN
        RAISE WARNING
            'recalculating standings for matchweek % in status %; results may be provisional',
            p_matchweek_id, v_week_status;
    END IF;

    SELECT COALESCE(MAX(calculation_version), 0) + 1
      INTO v_new_version
      FROM standings_snapshots
     WHERE matchweek_id = p_matchweek_id;

    INSERT INTO audit_logs (admin_user_id, entity_type, entity_id, action, new_values, reason)
    VALUES (
        v_admin, 'standings_snapshot', p_matchweek_id, 'recalculation_started',
        jsonb_build_object(
            'competition_group_id', v_group_id,
            'week_number', v_week_number,
            'calculation_version', v_new_version
        ),
        'Standings recalculation started'
    );

    WITH
    target_mw AS (
        SELECT mw.id AS matchweek_id, mw.competition_group_id, mw.week_number
          FROM matchweeks mw
         WHERE mw.id = p_matchweek_id
    ),
    group_rules AS (
        SELECT cg.id AS competition_group_id,
               cg.points_for_win, cg.points_for_draw, cg.points_for_loss
          FROM competition_groups cg
          JOIN target_mw tmw ON tmw.competition_group_id = cg.id
    ),
    all_results AS (
        SELECT
            m.home_registration_id,
            m.away_registration_id,
            CASE
                WHEN rv.outcome = 'abandoned' THEN 0::smallint
                ELSE rv.home_score
            END AS home_score,
            CASE
                WHEN rv.outcome = 'abandoned' THEN 0::smallint
                ELSE rv.away_score
            END AS away_score
          FROM matches m
          JOIN matchweeks mw2 ON mw2.id = m.matchweek_id
          JOIN target_mw tmw   ON tmw.competition_group_id = mw2.competition_group_id
          JOIN match_result_versions rv ON rv.id = m.current_result_version_id
         WHERE mw2.week_number <= tmw.week_number
           AND rv.outcome IN ('played', 'walkover', 'abandoned')
    ),
    per_team AS (
        SELECT
            tr.id                          AS team_registration_id,
            tmw.competition_group_id,
            tmw.matchweek_id,
            COUNT(ar.home_score)           AS played,
            COUNT(ar.home_score) FILTER (WHERE
                (ar.home_registration_id = tr.id AND ar.home_score > ar.away_score)
             OR (ar.away_registration_id = tr.id AND ar.away_score > ar.home_score)
            )                              AS won,
            COUNT(ar.home_score) FILTER (WHERE ar.home_score = ar.away_score)
                                           AS drawn,
            COUNT(ar.home_score) FILTER (WHERE
                (ar.home_registration_id = tr.id AND ar.home_score < ar.away_score)
             OR (ar.away_registration_id = tr.id AND ar.away_score < ar.home_score)
            )                              AS lost,
            COALESCE(SUM(CASE
                WHEN ar.home_registration_id = tr.id THEN ar.home_score
                WHEN ar.away_registration_id = tr.id THEN ar.away_score
            END), 0)                       AS goals_for,
            COALESCE(SUM(CASE
                WHEN ar.home_registration_id = tr.id THEN ar.away_score
                WHEN ar.away_registration_id = tr.id THEN ar.home_score
            END), 0)                       AS goals_against
          FROM team_registrations tr
          JOIN target_mw tmw ON tr.competition_group_id = tmw.competition_group_id
          LEFT JOIN all_results ar
            ON ar.home_registration_id = tr.id
            OR ar.away_registration_id = tr.id
         WHERE tr.registration_status = 'active'
         GROUP BY tr.id, tmw.competition_group_id, tmw.matchweek_id
    ),
    scored AS (
        SELECT pt.*,
               gr.points_for_win, gr.points_for_draw, gr.points_for_loss,
               (pt.won * gr.points_for_win
                + pt.drawn * gr.points_for_draw
                + pt.lost * gr.points_for_loss) AS points,
               (pt.goals_for - pt.goals_against)    AS goal_difference
          FROM per_team pt
          JOIN group_rules gr ON gr.competition_group_id = pt.competition_group_id
    ),
    ranked AS (
        SELECT s.*,
               ROW_NUMBER() OVER (
                   PARTITION BY s.matchweek_id
                   ORDER BY s.points DESC,
                            s.goal_difference DESC,
                            s.goals_for DESC,
                            s.team_registration_id
               ) AS position
          FROM scored s
    )
    INSERT INTO standings_snapshots (
        competition_group_id, matchweek_id, team_registration_id,
        played, won, drawn, lost, goals_for, goals_against, goal_difference,
        points, position, calculation_version,
        points_for_win_snapshot, points_for_draw_snapshot, points_for_loss_snapshot
    )
    SELECT
        r.competition_group_id, r.matchweek_id, r.team_registration_id,
        r.played, r.won, r.drawn, r.lost,
        r.goals_for, r.goals_against, r.goal_difference,
        r.points, r.position, v_new_version,
        r.points_for_win, r.points_for_draw, r.points_for_loss
    FROM ranked r;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;

    INSERT INTO audit_logs (admin_user_id, entity_type, entity_id, action, new_values, reason)
    VALUES (
        v_admin, 'standings_snapshot', p_matchweek_id, 'recalculation_completed',
        jsonb_build_object(
            'competition_group_id', v_group_id,
            'week_number', v_week_number,
            'calculation_version', v_new_version,
            'row_count', v_row_count
        ),
        'Standings recalculation completed'
    );

    RETURN v_new_version;
END $$;

-- ---------- Seed data ----------
INSERT INTO divisions (name, slug, level_order) VALUES
('Regional League','regional',1),
('Division 1','division-1',2),
('Division 2','division-2',3)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO regions (name, slug) VALUES ('Eastern','eastern'), ('Central','central')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO zones (name, code, region_id)
SELECT v.name, v.code, r.id
FROM (VALUES ('Zone A','A'),('Zone B','B'),('Zone C','C'),('Zone D','D')) AS v(name,code)
CROSS JOIN regions r
WHERE r.slug = 'eastern'
ON CONFLICT (region_id, code) DO NOTHING;