-- Meta AI: narrow path from '/' to '/api/graphql/' 
-- Research shows chat API uses GraphQL at /api/graphql/
-- This prevents blocking the entire meta.ai homepage
UPDATE etap.ai_prompt_services 
SET path_patterns = '/api/graphql/',
    description = 'Meta AI chat — GraphQL API endpoint'
WHERE service_name = 'meta';

-- Verify
SELECT service_name, domain_patterns, path_patterns, description
FROM etap.ai_prompt_services WHERE service_name = 'meta';
