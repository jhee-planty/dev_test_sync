-- CRITICAL FIX: copilot entry has domain_patterns='www.bing.com' + path='/'
-- This blocks ALL Bing traffic including regular web searches!
-- MS Copilot is now at copilot.microsoft.com (already covered by m365_copilot)
-- Fix: disable copilot entry since m365_copilot covers the correct domain

-- Option: disable copilot (www.bing.com catch-all is dangerous)
UPDATE etap.ai_prompt_services 
SET enabled = 'false', 
    description = 'DISABLED: domain www.bing.com blocks all Bing traffic. Use m365_copilot for copilot.microsoft.com'
WHERE service_name = 'copilot';

-- Verify
SELECT service_name, domain_patterns, path_patterns, enabled, description
FROM etap.ai_prompt_services 
WHERE service_name IN ('copilot', 'm365_copilot');
