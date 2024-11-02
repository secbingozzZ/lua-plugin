local pool_max_idle_time = 10000  -- Redis 连接池中连接的最大空闲时间（毫秒）
local pool_size = 100  -- Redis 连接池的最大连接数
local redis_connection_timeout = 100  -- Redis 连接超时时间（毫秒）
local redis_host = "127.0.0.1"  -- Redis 服务器的 IP 地址
local redis_port = "6379"  -- Redis 服务器的端口
local redis_auth = "zaq1@EDC"  -- Redis 服务器的认证密码
local ip_block_time = 60  -- 封禁时间 5 分钟（秒）
local ip_time_out = 1  -- IP 请求计数的过期时间（秒）
local ip_max_count = 30  -- IP 在 `ip_time_out` 时间内允许的最大请求次数

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

-- 获取客户端 IP
local clientIp = getIp()

-- Redis 键
local incrKey = "limit_count:" .. clientIp
local blockKey = "limit_ip:" .. clientIp

-- 检查 IP 是否被封禁
local is_block, err = client:get(blockKey)
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
end

-- 关闭 Redis 连接
close_redis(client)