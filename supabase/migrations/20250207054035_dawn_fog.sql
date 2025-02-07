/*
  # Complete Schema Setup

  1. Database Objects
    - Custom types for roles, races, equipment
    - Core tables: heroes, realms, items, quests
    - Junction tables: realm_members, hero_inventory, hero_equipment
  
  2. Security
    - Row Level Security (RLS) enabled on all tables
    - Policies for data access control
    - Validation triggers and functions
*/

-- Create custom types if they don't exist
DO $$ BEGIN
    CREATE TYPE realm_role AS ENUM ('owner', 'admin', 'member');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE hero_race AS ENUM ('elf', 'goblin', 'human', 'orc');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE equipment_slot AS ENUM ('helm', 'weapon', 'shield', 'armor', 'gloves');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE item_type AS ENUM ('helm', 'weapon', 'shield', 'armor', 'gloves', 'two_handed_weapon', 'robe');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create heroes table (users)
CREATE TABLE IF NOT EXISTS heroes (
  id uuid PRIMARY KEY DEFAULT auth.uid(),
  email text UNIQUE NOT NULL,
  display_name text NOT NULL,
  race hero_race NOT NULL DEFAULT 'human',
  coins integer NOT NULL DEFAULT 0,
  is_developer boolean DEFAULT false,
  is_paying_customer boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create realms table (households)
CREATE TABLE IF NOT EXISTS realms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_by uuid REFERENCES heroes(id) NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create realm_members junction table
CREATE TABLE IF NOT EXISTS realm_members (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  realm_id uuid REFERENCES realms(id) ON DELETE CASCADE,
  role realm_role NOT NULL DEFAULT 'member',
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, realm_id)
);

-- Create items table
CREATE TABLE IF NOT EXISTS items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  item_types item_type[] NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create hero inventory table
CREATE TABLE IF NOT EXISTS hero_inventory (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  item_id uuid REFERENCES items(id) ON DELETE CASCADE,
  quantity integer NOT NULL DEFAULT 1,
  acquired_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, item_id)
);

-- Create hero equipment table
CREATE TABLE IF NOT EXISTS hero_equipment (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  item_id uuid REFERENCES items(id) ON DELETE CASCADE,
  slot equipment_slot NOT NULL,
  equipped_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, slot)
);

-- Create quest_boards table
CREATE TABLE IF NOT EXISTS quest_boards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id uuid REFERENCES realms(id) ON DELETE CASCADE,
  name text NOT NULL,
  theme jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create quests table
CREATE TABLE IF NOT EXISTS quests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quest_board_id uuid REFERENCES quest_boards(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  difficulty integer NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  priority integer NOT NULL CHECK (priority BETWEEN 1 AND 5),
  recurrence_type text NOT NULL CHECK (recurrence_type IN ('once', 'daily', 'weekly')),
  recurrence_interval integer CHECK (
    (recurrence_type = 'weekly' AND recurrence_interval IS NOT NULL AND recurrence_interval > 0) OR
    (recurrence_type != 'weekly' AND recurrence_interval IS NULL)
  ),
  start_date date NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable Row Level Security
DO $$ BEGIN
    ALTER TABLE heroes ENABLE ROW LEVEL SECURITY;
    ALTER TABLE realms ENABLE ROW LEVEL SECURITY;
    ALTER TABLE realm_members ENABLE ROW LEVEL SECURITY;
    ALTER TABLE items ENABLE ROW LEVEL SECURITY;
    ALTER TABLE hero_inventory ENABLE ROW LEVEL SECURITY;
    ALTER TABLE hero_equipment ENABLE ROW LEVEL SECURITY;
    ALTER TABLE quest_boards ENABLE ROW LEVEL SECURITY;
    ALTER TABLE quests ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Drop existing policies if they exist
DO $$ BEGIN
    DROP POLICY IF EXISTS "Heroes can read own data" ON heroes;
    DROP POLICY IF EXISTS "Heroes can update own data" ON heroes;
    DROP POLICY IF EXISTS "Realm members can read realms" ON realms;
    DROP POLICY IF EXISTS "Anyone can read items" ON items;
    DROP POLICY IF EXISTS "Heroes can read own inventory" ON hero_inventory;
    DROP POLICY IF EXISTS "Heroes can read own equipment" ON hero_equipment;
    DROP POLICY IF EXISTS "Realm members can read quest boards" ON quest_boards;
    DROP POLICY IF EXISTS "Realm members can read quests" ON quests;
END $$;

-- Create policies
CREATE POLICY "Heroes can read own data" ON heroes
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Heroes can update own data" ON heroes
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Realm members can read realms" ON realms
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM realm_members
      WHERE realm_id = realms.id
      AND hero_id = auth.uid()
    )
  );

CREATE POLICY "Anyone can read items" ON items
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Heroes can read own inventory" ON hero_inventory
  FOR SELECT
  TO authenticated
  USING (hero_id = auth.uid());

CREATE POLICY "Heroes can read own equipment" ON hero_equipment
  FOR SELECT
  TO authenticated
  USING (hero_id = auth.uid());

CREATE POLICY "Realm members can read quest boards" ON quest_boards
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM realm_members
      WHERE realm_id = quest_boards.realm_id
      AND hero_id = auth.uid()
    )
  );

CREATE POLICY "Realm members can read quests" ON quests
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM realm_members rm
      JOIN quest_boards qb ON qb.realm_id = rm.realm_id
      WHERE qb.id = quests.quest_board_id
      AND rm.hero_id = auth.uid()
    )
  );

-- Create or replace functions for validation and automation
CREATE OR REPLACE FUNCTION validate_realm_creator()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM heroes 
    WHERE id = NEW.created_by 
    AND (is_developer = true OR is_paying_customer = true)
  ) THEN
    RAISE EXCEPTION 'Realm creator must be a developer or paying customer';
  END IF;
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE OR REPLACE FUNCTION validate_equipment_slot()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if the item can be equipped in the specified slot
  IF NOT EXISTS (
    SELECT 1 FROM items 
    WHERE id = NEW.item_id 
    AND (
      -- Direct slot match
      NEW.slot::text::item_type = ANY(item_types)
      OR
      -- Special case: two-handed weapons can go in weapon or shield slots
      (NEW.slot IN ('weapon', 'shield') AND 'two_handed_weapon' = ANY(item_types))
      OR
      -- Special case: robes can go in armor or helm slots
      (NEW.slot IN ('armor', 'helm') AND 'robe' = ANY(item_types))
    )
  ) THEN
    RAISE EXCEPTION 'Item cannot be equipped in the specified slot';
  END IF;
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE OR REPLACE FUNCTION check_two_handed_weapon()
RETURNS TRIGGER AS $$
BEGIN
  -- If equipping a two-handed weapon
  IF EXISTS (
    SELECT 1 FROM items 
    WHERE id = NEW.item_id 
    AND 'two_handed_weapon' = ANY(item_types)
  ) THEN
    -- Clear the other slot (weapon/shield)
    DELETE FROM hero_equipment 
    WHERE hero_id = NEW.hero_id 
    AND slot IN ('weapon', 'shield')
    AND slot != NEW.slot;
  END IF;
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Drop existing triggers if they exist
DO $$ BEGIN
    DROP TRIGGER IF EXISTS validate_realm_creator_trigger ON realms;
    DROP TRIGGER IF EXISTS validate_equipment_slot_trigger ON hero_equipment;
    DROP TRIGGER IF EXISTS enforce_two_handed_weapon ON hero_equipment;
    DROP TRIGGER IF EXISTS update_heroes_updated_at ON heroes;
    DROP TRIGGER IF EXISTS update_realms_updated_at ON realms;
    DROP TRIGGER IF EXISTS update_quest_boards_updated_at ON quest_boards;
    DROP TRIGGER IF EXISTS update_quests_updated_at ON quests;
END $$;

-- Create triggers
CREATE TRIGGER validate_realm_creator_trigger
  BEFORE INSERT OR UPDATE ON realms
  FOR EACH ROW
  EXECUTE FUNCTION validate_realm_creator();

CREATE TRIGGER validate_equipment_slot_trigger
  BEFORE INSERT OR UPDATE ON hero_equipment
  FOR EACH ROW
  EXECUTE FUNCTION validate_equipment_slot();

CREATE TRIGGER enforce_two_handed_weapon
  AFTER INSERT OR UPDATE ON hero_equipment
  FOR EACH ROW
  WHEN (NEW.slot IN ('weapon', 'shield'))
  EXECUTE FUNCTION check_two_handed_weapon();

CREATE TRIGGER update_heroes_updated_at
  BEFORE UPDATE ON heroes
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_realms_updated_at
  BEFORE UPDATE ON realms
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_quest_boards_updated_at
  BEFORE UPDATE ON quest_boards
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_quests_updated_at
  BEFORE UPDATE ON quests
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();