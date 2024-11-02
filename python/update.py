from blacklist import *
import schedule
import time
def main():
    try:
        password = 'your_password'
        r = connect_redis(password=password) 
    except Exception as e:
        print(f"连接到Redis数据库失败: {e}")
        return
    try:
        # 读取黑名单文件中的所有IP
        blacklist_ips = set()
        try:
            with open('/root/program/blackiplist', 'r') as blacklist_file:
                blacklist_ips = set(line.strip() for line in blacklist_file if line.strip())
        except FileNotFoundError:
            print("黑名单文件未找到，跳过黑名单处理。")
            return
        except Exception as e:
            print(f"读取黑名单文件时出错: {e}")
            return

        # 读取白名单文件中的IP
        whitelist_ips = set()
        try:
            with open('/root/program/whitelist', 'r') as whitelist_file:
                whitelist_ips = set(line.strip() for line in whitelist_file if line.strip())
        except FileNotFoundError:
            print("白名单文件未找到，跳过白名单处理。")
        except Exception as e:
            print(f"读取白名单文件时出错: {e}")
            return

        # 从黑名单中删除白名单中的IP
        remaining_ips = blacklist_ips - whitelist_ips

        # 将剩余的IP写入limitip文件
        try:
            with open('/root/program/limitip', 'w') as limitip_file:
                for ip in remaining_ips:
                    limitip_file.write(f"{ip}\n")
            print("已将剩余IP写入limitip文件。")
        except Exception as e:
            print(f"写入limitip文件时出错: {e}")
            return
        # 将剩余的IP写入黑名单文件
        try:
            with open('/root/program/blackiplist', 'w') as blacklist_file:
                for ip in remaining_ips:
                    blacklist_file.write(f"{ip}\n")
            print("已将剩余IP覆盖写入黑名单文件。")
        except Exception as e:
            print(f"写入黑名单文件时出错: {e}")
            return
        # 删除白名单中的IP
        def remove_ip_from_redis(ip):
            if r.hexists('blacklist', ip):
                r.hdel('blacklist', ip)
                print(f"已将白名单IP {ip} 从Redis中删除。")
            else:
                print(f"白名单IP {ip} 不在Redis中，跳过删除。")

        for ip in whitelist_ips:
            if ip:
                remove_ip_from_redis(ip)

        # 读取limitip文件并更新到Redis
        with open('/root/program/limitip', 'r') as limitip_file:
            limit_ips = [line.strip() for line in limitip_file if line.strip()]

        for ip in limit_ips:
            add_blacklist_ip(r, ip)

        print("已将limitip文件中的IP更新到Redis数据库。")
    except Exception as e:
        print(f"更新黑名单时出错: {e}")
        return


def job():
    try:
        main()
    except Exception as e:
        print(f"定时任务执行时出错: {e}")
        return  # 确保在发生异常时退出任务

# 每30分钟执行一次更新任务
schedule.every(30).minutes.do(job)

def run_scheduler():
    while True:
        schedule.run_pending()
        time.sleep(1)

if __name__ == '__main__':
    try:
        run_scheduler()
    except KeyboardInterrupt:
        print("定时任务已手动终止。")
