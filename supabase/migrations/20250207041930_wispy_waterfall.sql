-- Create new types
CREATE TYPE hero_race AS ENUM ('elf', 'goblin', 'human', 'orc');
CREATE TYPE equipment_slot AS ENUM ('helm', 'weapon', 'shield', 'armor', 'gloves');
CREATE TYPE item_type AS ENUM ('helm', 'weapon', 'shield', 'armor', 'gloves', 'two_handed_weapon', 'robe');

-- Add new columns to heroes
ALTER TABLE heroes ADD COLUMN IF NOT EXISTS race hero_race NOT NULL DEFAULT 'human';
ALTER TABLE heroes ADD COLUMN IF NOT EXISTS coins integer NOT NULL DEFAULT 0;

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

-- Enable RLS
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_equipment ENABLE ROW LEVEL SECURITY;

-- Create policies

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

-- Create function to validate equipment slot
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

-- Create trigger for equipment slot validation
CREATE TRIGGER validate_equipment_slot_trigger
  BEFORE INSERT OR UPDATE ON hero_equipment
  FOR EACH ROW
  EXECUTE FUNCTION validate_equipment_slot();

-- Create function to handle two-handed weapons
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

-- Create trigger for two-handed weapons
CREATE TRIGGER enforce_two_handed_weapon
  AFTER INSERT OR UPDATE ON hero_equipment
  FOR EACH ROW
  WHEN (NEW.slot IN ('weapon', 'shield'))
  EXECUTE FUNCTION check_two_handed_weapon();