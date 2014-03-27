_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
pty = require 'pty.js'

module.exports = class MuxSocket extends RainbowSocket
  namespace: 'mux'

  initialize: ->
    this.on 'start', _.bind(@onStart,  this)
    this.on 'kill',  _.bind(@onKill,   this)
    this.on 'listAll', _.bind(@onListAll, this)
    @sshStarted = false
    @mux = undefined

  destroy: ->
    @sshStarted = false
    @mux?.removeAllListeners()
    @mux?.destroy()
    @mux = undefined

  onStart: (boxId, termId, ack) ->
    @sshStarted = false
    return ack?('pty already created') if @pty
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      this.connectToSSH box, keyPair, termId, (error) =>
        return ack?('failed to create ssh connection') if error
        ack?()

  onKill: ->
    this.destroy()

  connectToSSH: (box, keyPair, termId, callback) ->
    @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        callback err
        return
      # start gomux in a background process and attach to the term id
      try
        muxArgs = _.clone sshArgs
        muxArgs.push("-t") # force tty allocation so we can interrupt gomux events
        muxArgs.push("gomux events")
        @mux = pty.spawn "/usr/bin/ssh", muxArgs
      catch err
        deleteKeyFile ->
          callback err
        return
      @mux.once 'data', =>
        deleteKeyFile()
        @sshStarted = true
      @mux.on 'data',  _.bind(@onMuxEvents, this)
      @mux.on 'close',  _.bind(@onMuxClose, this)
      callback null

  # list all current sessions
  onListAll: (ack) ->
    @ssh.execCommand "gomux", (err, stdout, stderr) ->
      return ack?(err.toString(), null) if err
      try
        data = JSON.parse stdout
        console.log data
        return ack? null, data
      catch err
        return ack?(err.toString(), null)

  onMuxEvents: (data) ->
    try
      this.send 'mux', JSON.parse(data)
    catch err
      console.log "ERROR: #{err}, data: #{data}"

  onMuxClose: (hadError) ->
    this.send 'close'
    this.destroy()
