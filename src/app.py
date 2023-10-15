from flask import Flask, request

app = Flask(__name__)

@app.route('/')
def ip_client():
    output = ''
    ip_addr = request.remote_addr
    output += '                        IP address: ' + ip_addr + '\n'
    ip_addr = request.environ['REMOTE_ADDR']
    output += 'REMOTE_ADDR:            IP address: ' + ip_addr + '\n'
    ip_addr = request.environ.get('HTTP_X_FORWARDED_FOR', request.remote_addr)
    output += 'HTTP_X_FORWARDED_FOR:   IP address: ' + ip_addr + '\n'
    return output

if __name__ == '__main__':
    app.run(debug=True)
