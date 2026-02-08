-- Fix api_server URLs for local Docker environment
-- Original dump has external IP (35.201.245.248), replace with Docker internal hostname
UPDATE api_server SET url = 'http://backend:9986/channel/channelHandle?' WHERE sid = 1;

-- Fix agent to match platform's sub-agent (test5, id=5)
-- Platform uses agent table PK (id) as the agent identifier in channelHandle API
-- Top agents (top_agent_id=-1) are rejected, must use a sub-agent
UPDATE agent SET agent_id = '5', md5_key = '28b0225fd10502f0', aes_key = 'c09216abccb73ddf' WHERE aid = 80;
