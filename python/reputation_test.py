from flask import Flask, request, jsonify
import random

app = Flask(__name__)

@app.route('/get_reputation', methods=['GET'])
def get_reputation():
    # 获取请求中的IP参数
    ip = request.args.get('ip')
    
    if not ip:
        return jsonify({"error": "IP address is required"}), 400
    
    # 生成一个100以内的随机整数
    reputation_number = random.randint(70, 90)
    
    # 返回结果
    return jsonify({
        "ip": ip,
        "reputation_number": reputation_number
    })

if __name__ == '__main__':
    app.run(debug=True, port=9898)
