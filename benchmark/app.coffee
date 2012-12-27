cluster = require 'cluster'
http    = require 'http'
numCPUs = require('os').cpus().length
io      = require('socket.io-client')

# configurations
DURATION = 240000
SHUT_DOWN_AFTER = 250000
secret  = "#secret_key_here"
origin  = "https://dev.action.io:5000"
sftpUrl = "https://dev.action.io:5001/ws/sftp"
sshUrl  = "https://dev.action.io:5001/ws/ssh"
boxId   = 61
numUser = process.argv[2]

# patching socket.io http client to include some necessary cookie
{ XMLHttpRequest } = require('./patch-xmlhttprequest')
Socket = require('ws')

io.util.request = (xdomain) ->
  request = new XMLHttpRequest()
  # hard-coded session cookie. this is going to be
  # { session_id: 'sessionid',
  #   _csrf_token: 'csrf token',
  #   'warden.user.user.key': [ 'User', [ 6 ], 'some string ...' ] }
  old_send = request.send
  old_open = request.open
  request.open = -> old_open.apply this, arguments
  request.send = (data) ->
    this.setRequestHeader 'cookie', '#cooke_here'
    this.setRequestHeader 'origin', origin
    old_send.apply this, data
  return request

# Patch WebSocket to have custom origin
io.Transport.websocket.prototype.open = ->
  query = io.util.query(this.socket.options.query)
  @websocket = new Socket(@prepareUrl() + query, origin: origin)
  @websocket.onopen =  =>
    this.onOpen()
    @socket.setBuffer(false)
  @websocket.onclose = =>
    this.onClose()
    @socket.setBuffer(true)
  @websocket.onmessage = (ev) =>
    this.onData(ev.data)
  @websocket.onerror = (e) => this.onError(e)
  return this

# SSH Worker
# ==========
# This defines request pattern that we are going to hit SSH endpoints of
# rainbow with.
class SSHWorker
  # id - id of the worker. Most likely this is going to be the order number in
  # the list of users
  constructor: (@id) ->
  start: ->
    @socket = socket = io.connect sshUrl, 'force new connection': true
    socket.on 'p', (data) -> console.log "data::1"
    socket.on 'connect', =>
      console.log "connected"
      socket.emit 'start', boxId, (err) ->
        console.log "started"
        return if err
        socket.emit 'r', 80, 6
        setInterval ->
          socket.emit 'd', "l"
          socket.emit 'd', "s"
          socket.emit 'd', "\r"
        , 100
    setTimeout =>
      console.log("Finish 1 minute. disconnect now.")
      socket.disconnect()
    , DURATION

# start a cluster master
startMaster = ->
  for i in [1..numCPUs]
    worker = cluster.fork()
    setTimeout ->
      console.log("kill the worker now")
      process.exit 0
    , SHUT_DOWN_AFTER

  cluster.on 'exit', (worker, code, signal) ->
    console.log "worker #{worker.process.pid} died with code: #{code} and signal #{signal}"

# start a cluster worker, each process will start `numUser` number of worker
startWorker = ->
  workers = (new SSHWorker(i) for i in [1..numUser])
  intervalId = setInterval =>
    if workers.length == 0
      clearInterval(intervalId)
      return
    worker = workers.pop()
    worker.start()
  , 1000

if cluster.isMaster then startMaster() else startWorker()
