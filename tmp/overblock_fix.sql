-- Fix over-blocking: narrow path patterns for multi-purpose domains

-- huggingface.co: AI chat is at /chat, rest is model hub/docs
-- Blocking all of huggingface.co would break ML workflows
UPDATE etap.ai_prompt_services 
SET path_patterns = '/chat',
    description = 'HuggingFace AI Chat only — /chat path. Model hub/docs unblocked.'
WHERE service_name = 'huggingface';

-- you.com: AI search is at /search with chat, but the domain serves regular search too
-- For now, narrow to /search to avoid blocking non-AI pages
UPDATE etap.ai_prompt_services 
SET path_patterns = '/search',
    description = 'You.com AI search — /search path. Other pages unblocked.'
WHERE service_name = 'you';

-- Verify
SELECT service_name, domain_patterns, path_patterns, description
FROM etap.ai_prompt_services 
WHERE service_name IN ('huggingface', 'you');
