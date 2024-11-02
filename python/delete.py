from blacklist import *

def main():
    try: 
        r = connect_redis()
    except Exception as e:
        print(f"连接到Redis数据库失败: {e}")
        return
    try:
        ip = input("请输入要删除的IP地址: ")
        remove_blacklist_ip(r, ip)
    except Exception as e:
        print(f"删除黑名单IP失败: {e}")
        return
    try:
        with open('/root/program/iplist', 'r') as file:
            lines = file.readlines()
        
        with open('/root/program/iplist', 'w') as file:
            for line in lines:
                if line.strip() != ip:
                    file.write(line)
            print(f"已从文件中删除IP {ip}。")
    except FileNotFoundError:
        print("文件 /root/program/iplist 未找到。")
    except Exception as e:
        print(f"从文件中删除IP失败: {e}")

if __name__ == '__main__':
    main()