import redis
import json

def connect_redis(host='localhost', port=6379, db=0, password='your_passworrd'):
    """
    连接Redis数据库。

    :param host: Redis服务器地址，默认是localhost
    :param port: Redis端口，默认是6379
    :param db: 数据库编号，默认是0
    :param password: Redis密码，如果有的话
    :return: Redis连接对象
    """
    pool = redis.ConnectionPool(host=host, port=port, db=db, password=password)
    r = redis.Redis(connection_pool=pool)
    return r

def add_blacklist_ip(r, ip, ban_time = 'unknown', ban_reason = 'unknown'):
    """
    添加黑名单IP到Redis哈希表中。

    :param r: Redis连接对象
    :param ip: 要封禁的IP地址
    :param ban_time: 封禁时间
    :param ban_reason: 封禁原因
    """
    key = 'blacklist'
    value = json.dumps({
        'BanTime': ban_time,
        'BanReason': ban_reason
    })
    r.hset(key, ip, value)
    print(f"已将IP {ip} 添加到黑名单。")

def get_blacklist_ip(r, ip):
    """
    获取指定IP的封禁信息。

    :param r: Redis连接对象
    :param ip: 要查询的IP地址
    :return: 封禁信息的字典，包含BanTime和BanReason
    """
    key = 'blacklist'
    value = r.hget(key, ip)
    if value:
        return json.loads(value)
    else:
        print(f"IP {ip} 不在黑名单中。")
        return None

def remove_blacklist_ip(r, ip):
    """
    从黑名单中删除指定的IP。

    :param r: Redis连接对象
    :param ip: 要删除的IP地址
    :return: 如果成功删除，返回True；如果IP不在黑名单中，返回False
    """
    key = 'blacklist'
    if r.hexists(key, ip):
        r.hdel(key, ip)
        print(f"已将IP {ip} 从黑名单中删除。")
        return True
    else:
        print(f"IP {ip} 不在黑名单中。")
        return False

def get_all_blacklist(r):
    """
    获取所有黑名单IP的信息。

    :param r: Redis连接对象
    :return: 包含所有黑名单IP信息的字典
    """
    key = 'blacklist'
    all_entries = r.hgetall(key)
    blacklist = {}
    for ip, value in all_entries.items():
        ip = ip.decode('utf-8')
        data = json.loads(value.decode('utf-8'))
        blacklist[ip] = data
    return blacklist

if __name__ == "__main__":
    # 连接到Redis数据库
    password = input("请输入Redis数据库的密码: ")
    redis_conn = connect_redis(host='localhost', port=6379, db=0, password=password)

    # 添加黑名单IP示例
    ip_address = '192.168.1.102'
    ban_time = '2023-10-28 14:00:00'
    ban_reason = '检测到可疑活动'
    add_blacklist_ip(redis_conn, ip_address, ban_time, ban_reason)
    #add_blacklist_ip(redis_conn, ip_address)
    # 获取指定IP的封禁信息
    info = get_blacklist_ip(redis_conn, ip_address)
    if info:
        print(f"IP地址: {ip_address}")
        print(f"封禁时间: {info['BanTime']}")
        print(f"封禁原因: {info['BanReason']}")

    # 删除黑名单IP示例
    #remove_blacklist_ip(redis_conn, ip_address)

    # 获取所有黑名单IP的信息
    all_blacklist = get_all_blacklist(redis_conn)
    print("当前黑名单IP列表：")
    for ip, details in all_blacklist.items():
        print(f"IP地址: {ip}, 封禁时间: {details['BanTime']}, 封禁原因: {details['BanReason']}")

