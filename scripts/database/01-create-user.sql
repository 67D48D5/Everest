-- ---------------------------------------------------------
-- SECURITY WARNING:
-- This script contains hardcoded credentials for development.
-- DO NOT USE IN PRODUCTION without changing passwords or
-- using environment variables/secrets management.
-- ---------------------------------------------------------

-- Create the local user with the specified password
CREATE USER '46770d6'@'localhost' IDENTIFIED BY '7f04916';

-- Grant all privileges to the user on all databases
GRANT ALL PRIVILEGES ON *.* TO '46770d6'@'localhost';

-- Apply the changes
FLUSH PRIVILEGES;