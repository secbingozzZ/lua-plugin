local pool_max_idle_time = 10000  -- Redis 连接池中连接的最大空闲时间（毫秒）
local pool_size = 100  -- Redis 连接池的最大连接数
local redis_connection_timeout = 100  -- Redis 连接超时时间（毫秒）
local redis_host = "127.0.0.1"  -- Redis 服务器的 IP 地址
local redis_port = "6379"  -- Redis 服务器的端口
local redis_auth = "zaq1@EDC"  -- Redis 服务器的认证密码
local ip_block_time = 10  -- 对 IP 进行封禁的时间（秒）
local ip_time_out = 5  -- IP 请求计数的过期时间（秒）
local ip_max_count = 20  -- IP 在 `ip_time_out` 时间内允许的最大请求次数

-- 错误日志函数
local function errlog(msg, ex)
    ngx.log(ngx.ERR, msg, ex)
end

-- 关闭 Redis 连接的函数
local function close_redis(red)
    if not red then
        return
    end
    local ok, err = red:set_keepalive(pool_max_idle_time, pool_size)
    if not ok then
        ngx.say("redis connct err:", err)
        return red:close()
    end
end

-- 初始化 Redis 客户端
local redis = require "resty.redis"
local client = redis:new()
local ok, err = client:connect(redis_host, redis_port)

if not ok then
    close_redis(client)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

client:set_timeout(redis_connection_timeout)

-- Redis 连接重用逻辑
local connCount, err = client:get_reused_times()

if 0 == connCount then
    local ok, err = client:auth(redis_auth)
    if not ok then
        errlog("failed to auth: ", err)
        return
    end
elseif err then
    errlog("failed to get reused times: ", err)
    return
end

-- 获取客户端 IP 的函数
local function getIp()
    local clientIP = ngx.req.get_headers()["X-Real-IP"]
    if clientIP == nil then
        clientIP = ngx.req.get_headers()["x_forwarded_for"]
    end
    if clientIP == nil then
        clientIP = ngx.var.remote_addr
    end
    return clientIP
end

-- 添加 IP 到黑名单
local function add_to_blacklist(ip, block_time)
    local blockKey = "limit:block:" .. ip
    local ok, err = client:set(blockKey, 1)
    if not ok then
        errlog("failed to add to blacklist: ", err)
        return false
    end
    if block_time then
        local ok, err = client:expire(blockKey, block_time)
        if not ok then
            errlog("failed to set expire for blacklist: ", err)
            return false
        end
    end

    -- 将 IP 添加到 Redis 集合
    local res, err = client:sismember("blacklist:ips", ip)
    if err then
        errlog("failed to check if IP is in blacklist: ", err)
        return false
    end

    if res == 0 then  -- IP 不在黑名单中
        local ok, err = client:sadd("blacklist:ips", ip)
        if not ok then
            errlog("failed to add IP to blacklist set: ", err)
            return false
        end
    end

    return true
end

-- 从黑名单中移除 IP
local function remove_from_blacklist(ip)
    local blockKey = "limit:block:" .. ip
    local ok, err = client:del(blockKey)
    if not ok then
        errlog("failed to remove from blacklist: ", err)
        return false
    end

    -- 从 Redis 集合中删除 IP
    client:srem("blacklist:ips", ip)
    return true
end

-- 检查 IP 是否在黑名单中
-- local function is_ip_in_blacklist(ip)
--     local res, err = client:sismember("blacklist:ips", ip)
--     if err then
--         errlog("failed to check blacklist: ", err)
--         return false
--     end
--     return res == 1
-- end

-- 动态添加、移除或查看黑名单的接口
local function handle_blacklist_request()
    local args = ngx.req.get_uri_args()
    local action = args["action"]
    local ip = args["ip"]
    local block_time = tonumber(args["block_time"]) or nil

    if action == "add" then
        if not ip then
            ngx.say("No IP provided.")
            return
        end
        local success = add_to_blacklist(ip, block_time)
        if success then
            ngx.say("IP " .. ip .. " added to blacklist.")
        else
            ngx.say("Failed to add IP to blacklist.")
        end
    elseif action == "remove" then
        if not ip then
            ngx.say("No IP provided.")
            return
        end
        local success = remove_from_blacklist(ip)
        if success then
            ngx.say("IP " .. ip .. " removed from blacklist.")
        else
            ngx.say("Failed to remove IP from blacklist.")
        end
    elseif action == "list" then
        -- 获取黑名单中的所有 IP
        local res, err = client:smembers("blacklist:ips")
        if err then
            errlog("failed to get blacklist: ", err)
            ngx.say("Failed to retrieve blacklist.")
            return
        end

        -- 如果黑名单为空
        if #res == 0 then
            ngx.say("Blacklist is empty.")
        else
            local blacklist_info = {}
            for _, ip in ipairs(res) do
                local blockKey = "limit:block:" .. ip
                -- 获取封禁剩余时间
                local ttl, err = client:ttl(blockKey)
                if err then
                    errlog("failed to get TTL for IP " .. ip .. ": ", err)
                    ttl = "unknown"
                elseif ttl == -1 then
                    ttl = "permanent"  -- 永久封禁
                elseif ttl == -2 then
                    ttl = "not blocked"  -- 该键不存在，IP 可能已经被解禁
                end
                table.insert(blacklist_info, ip .. " (TTL: " .. ttl .. " seconds)")
            end
            ngx.say("Blacklist IPs: ", table.concat(blacklist_info, ", "))
        end
    else
        ngx.say("Invalid action. Use 'add', 'remove', or 'list'.")
    end
end



-- 如果请求是用于管理黑名单的请求
if ngx.var.uri == "/manage_blacklist" then
    handle_blacklist_request()
    close_redis(client)
    return
end

-- 获取客户端 IP
local clientIp = getIp()

-- Redis 键
local incrKey = "limit:count:" .. clientIp
local blockKey = "limit:block:" .. clientIp

-- 检查 IP 是否被封禁或在黑名单中
local is_block, err = client:get(blockKey)
-- if tonumber(is_block) == 1 or is_ip_in_blacklist(clientIp) then
if tonumber(is_block) == 1 then
    ngx.exit(ngx.HTTP_FORBIDDEN)
    close_redis(client)
    return
end

-- 增加 IP 请求计数
local ip_count, err = client:incr(incrKey)
if tonumber(ip_count) == 1 then
    client:expire(incrKey, ip_time_out)
end

-- 如果请求次数超过最大限制，封禁 IP
if tonumber(ip_count) > tonumber(ip_max_count) then
    client:set(blockKey, 1)
    client:expire(blockKey, ip_block_time)
    client:sadd("blacklist:ips", clientIp)  -- 将 IP 添加到黑名单集合
end

-- 关闭 Redis 连接
close_redis(client)

