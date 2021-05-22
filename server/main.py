import os
from queue import Queue
from collections import namedtuple
from functools import wraps

from flask import Flask, request

os.system('')
app = Flask(__name__)


class UserData:
    def __init__(self, name, password):
        self.name = name
        self.messages = Queue()
        #self.salt = os.urandom(128)
        self.password = password


users = {
    "Grub4K": UserData("Grub4K", "123"),
    "foofy": UserData("foofy", "1234"),
    "sintrode": UserData("sintrode", "12345"),
}

usertokens = {}

def require_token(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        token = request.form.get('token')
        username = usertokens.get(bytes.fromhex(token))
        user = users.get(username)
        if user:
            return f(user, *args, **kwargs)
        else:
            return False
    return wrapper


def protocol_response(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        data = []
        succeeded = f(*args, **kwargs)
        if isinstance(succeeded, tuple):
            succeeded, *data = succeeded
        return '\n'.join([
            'success' if succeeded else 'fail',
            *data
        ])
    return wrapper


# TODO: fix hex usage
def gen_user_token(username):
    token = os.urandom(128)
    while token in usertokens:
        token = os.urandom(128)
    usertokens[token] = username
    return token.hex()


@app.route('/signup', methods=['POST'])
@protocol_response
def signup():
    return False
    username = request.form.get('username')
    if username not in users:
        password = request.form.get('password')
        if password:
            users[username] = UserData(password)
            return True
    return False


@app.route('/salt', methods=['POST'])
@protocol_response
def salt():
    return False
    username = request.form.get('username')
    if username not in users:
        return False
    return True, users[username].salt.hex()

@app.route('/login', methods=['POST'])
@protocol_response
def login():
    username = request.form.get('username')
    if username not in users:
        return False
    user = users[username]
    password = request.form.get('password')
    if user.password != password:
        return False
    return True, gen_user_token(username)

@app.route('/send', methods=['POST'])
@protocol_response
@require_token
def send(user):
    message = request.form.get('message')
    for other_user in users.values():
        other_user.messages.put('{}:{}'.format(user.name, message))
    return True

@app.route('/recv', methods=['POST'])
@protocol_response
@require_token
def recv(user):
    if not user.messages.empty():
        message = 'MSG ' + user.messages.get()
    else:
        message = 'END'
    return True, message

@app.route('/logout', methods=['POST'])
@protocol_response
@require_token
def logout(user):
    token = request.form['token']
    try:
        del usertokens[token]
    except:
        return False
    return True

@app.route('/')
def root():
    return '''<html>
<head><title>BatChat v0.1</title></head>
<body>
    <h1>BatChat</h1>
    <p>This is a BatChat protocol endpoint.<br>Please use a BatChat Client to connect to it.</p>
</body>
<!--
BatChat v1.0
-->
</html>'''

if __name__=='__main__':
    app.run() #host="0.0.0.0"
