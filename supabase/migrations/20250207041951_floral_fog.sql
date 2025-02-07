-- Create custom types
CREATE TYPE realm_role AS ENUM ('owner', 'admin', 'member');

-- Create heroes table (users)
CREATE TABLE heroes (
  id uuid PRIMARY KEY DEFAULT auth.uid(),
  email text UNIQUE NOT NULL,
  display_name text NOT NULL,
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

-- Create function to validate realm creator
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

-- Create trigger for realm creator validation
CREATE TRIGGER validate_realm_creator_trigger
  BEFORE INSERT OR UPDATE ON realms
  FOR EACH ROW
  EXECUTE FUNCTION validate_realm_creator();

-- Create realm_members junction table
CREATE TABLE realm_members (
  hero_id uuid REFERENCES heroes(id) ON DELETE CASCADE,
  realm_id uuid REFERENCES realms(id) ON DELETE CASCADE,
  role realm_role NOT NULL DEFAULT 'member',
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (hero_id, realm_id)
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

-- Create functions for updating timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updating timestamps
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