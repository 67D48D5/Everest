-- Create the local user with the specified password
CREATE USER '46770d6'@'localhost' IDENTIFIED BY '7f04916';

-- Grant all privileges to the user on all databases
GRANT ALL PRIVILEGES ON *.* TO '46770d6'@'localhost';

-- Apply the changes
FLUSH PRIVILEGES;