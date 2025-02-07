/*
  # Game System Schema

  1. Base Types
    - Create all enum types for heroes, equipment, and items
  2. Core Tables
    - heroes (base user table)
    - realms (groups/households)
    - realm_members (group membership)
  3. Equipment System
    - items (available items)
    - hero_inventory (owned items)
    - hero_equipment (equipped items)
  4. Security
    - Enable RLS on all tables
    - Add appropriate policies
*/

-- Create custom types
CREATE TYPE realm_role AS ENUM ('owner', 'admin', 'member');
CREATE TYPE hero_race AS ENUM ('elf', 'goblin', 'human', 'orc');
CREATE TYPE equipment_slot AS ENUM ('helm', 'weapon', 'shield', 'armor', 'gloves');
CREATE TYPE item_type AS ENUM ('helm', 'weapon', 'shield', 'armor', 'gloves', 'two_handed_weapon', 'robe');

-- Create heroes table (users)
CREATE TABLE heroes (
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
CREATE TABLE realms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_by uuid REFERENCES heroes(id) NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create realm_members junction table
CREATE TABLE realm_members (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  realm_id uuid REFERENCES realms(id) ON DELETE CASCADE,
  role realm_role NOT NULL DEFAULT 'member',
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, realm_id)
);

-- Create items table
CREATE TABLE items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  item_types item_type[] NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create hero inventory table
CREATE TABLE hero_inventory (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  item_id uuid REFERENCES items(id) ON DELETE CASCADE,
  quantity integer NOT NULL DEFAULT 1,
  acquired_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, item_id)
);

-- Create hero equipment table
CREATE TABLE hero_equipment (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  item_id uuid REFERENCES items(id) ON DELETE CASCADE,
  slot equipment_slot NOT NULL,
  equipped_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, slot)
);

-- Create quest_boards table
CREATE TABLE quest_boards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  realm_id uuid REFERENCES realms(id) ON DELETE CASCADE,
  name text NOT NULL,
  theme jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create quests table
CREATE TABLE quests (
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
ALTER TABLE heroes ENABLE ROW LEVEL SECURITY;
ALTER TABLE realms ENABLE ROW LEVEL SECURITY;
ALTER TABLE realm_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_boards ENABLE ROW LEVEL SECURITY;
ALTER TABLE quests ENABLE ROW LEVEL SECURITY;

-- Create policies

-- Heroes can read their own data
CREATE POLICY "Heroes can read own data" ON heroes
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- Heroes can update their own data
CREATE POLICY "Heroes can update own data" ON heroes
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- Realm policies
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

-- Everyone can read items
CREATE POLICY "Anyone can read items" ON items
  FOR SELECT
  TO authenticated
  USING (true);

-- Heroes can read their own inventory
CREATE POLICY "Heroes can read own inventory" ON hero_inventory
  FOR SELECT
  TO authenticated
  USING (hero_id = auth.uid());

-- Heroes can read their own equipment
CREATE POLICY "Heroes can read own equipment" ON hero_equipment
  FOR SELECT
  TO authenticated
  USING (hero_id = auth.uid());

-- Quest board policies
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

-- Quest policies
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

-- Create functions for validation and automation

-- Function to validate realm creator
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

-- Function to validate equipment slot
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

-- Function to handle two-handed weapons
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

-- Function to update timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers

-- Realm creator validation
CREATE TRIGGER validate_realm_creator_trigger
  BEFORE INSERT OR UPDATE ON realms
  FOR EACH ROW
  EXECUTE FUNCTION validate_realm_creator();

-- Equipment slot validation
CREATE TRIGGER validate_equipment_slot_trigger
  BEFORE INSERT OR UPDATE ON hero_equipment
  FOR EACH ROW
  EXECUTE FUNCTION validate_equipment_slot();

-- Two-handed weapon handling
CREATE TRIGGER enforce_two_handed_weapon
  AFTER INSERT OR UPDATE ON hero_equipment
  FOR EACH ROW
  WHEN (NEW.slot IN ('weapon', 'shield'))
  EXECUTE FUNCTION check_two_handed_weapon();

-- Updated timestamp triggers
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