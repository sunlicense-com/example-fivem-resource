-- SunLicense settings. scripts/package.sh fills these in from your environment when it builds the
-- resource you sell; keep real values out of git (this file stays empty here).
SunLicenseSettings = {
    url = 'https://api.sunlicense.com',
    -- An API key (slk_...) from the dashboard's API keys page. It can only validate licenses.
    apiKey = '',
    -- The ownership notice printed at start-up: "<product> is licensed software by <owner>. License AX8P-XXXX-…".
    product = 'My Resource',
    owner = 'You',
    terms = '', -- optional: a link to your terms
}
