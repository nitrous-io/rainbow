BaseSocket = require './base_socket'
Box = require '../models/box'
SSHHelper = require '../lib/ssh_helper'
_ = require 'underscore'

module.exports = class FSSocket extends BaseSocket
  constructor: (@socket) ->
    super(@socket)
    @socket.on 'start', this.onStart
    @socket.on 'list', this.onList
    @socket.on 'new', this.onNew
    @socket.on 'read', this.onRead
    @socket.on 'write', this.onWrite
    @socket.on 'delete', this.onDelete

  onStart: (boxId) =>
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        @socket.emit('start', err.toString())
        return
      unless box
        @socket.emit('start', 'box not found')
        return
      if box.owner_id != @user.id
        @socket.emit('start', "box doesn't belong to user")
        return
      @box = box
      @box.findKeyPair (err, keyPair) =>
        if err
          @socket.emit('start', err.toString())
          return
        unless keyPair
          @socket.emit('start', 'key pair not found')
          return

        @sshHelper = new SSHHelper('action', @box.host, @box.port, keyPair.private_key)
        @socket.emit('start')

  onList: (path) =>
    escapedPath = FSSocket.escape(path)
    @sshHelper?.execCommand "ls -1bp ~/#{escapedPath}", (err, stdout, stderr) =>
      if err
        @socket.emit('list', err.toString(), path)
        return
      stdout = stdout.trim()

      files = if stdout.length == 0
        []
      else
        stdout.replace(/\\ /g, ' ').split("\n")

      files = _.filter(files, (file) -> file.indexOf("\\") == -1)
      @socket.emit('list', null, path, files)

  onNew: (path, content, callbackId) =>
    escapedPath = FSSocket.escape(path)
    escapedContent = FSSocket.escape(content)
    if path.match /\/$/
      cmd = "mkdir -p ~/#{escapedPath}"
    else
      cmd = "if [ -d ~/#{escapedPath} ]; then echo 'aio_folder_exists' > /dev/stderr; exit 1; elif [ -e ~/#{escapedPath} ]; then echo 'aio_file_exists' > /dev/stderr; exit 1; else echo #{escapedContent} > ~/#{escapedPath}; fi"
    @sshHelper?.execCommand cmd, (err, stdout, stderr) =>
      if err
        @socket.emit('new', err.toString(), path, callbackId)
        return
      @socket.emit('new', null, path, callbackId)

  onRead: (path) =>
    escapedPath = FSSocket.escape(path)
    @sshHelper?.execCommand "if (file ~/#{escapedPath} | grep -q 'empty\\|text\\|very\\ short'); then cat ~/#{escapedPath}; else echo -n 'aio_not_text_file' > /dev/stderr; exit 1; fi", (err, stdout, stderr) =>
      if err
        @socket.emit('read', err.toString(), path)
        return
      @socket.emit('read', null, path, stdout.slice(0, -1))

  onWrite: (path, content) =>
    escapedPath = FSSocket.escape(path)
    escapedContent = FSSocket.escape(content)
    @sshHelper?.execCommand "echo #{escapedContent} > ~/#{escapedPath}", (err, stdout, stderr) =>
      if err
        @socket.emit('write', err.toString(), path)
        return
      @socket.emit('write', null, path)

  onDelete: (path) =>
    escapedPath = FSSocket.escape(path)
    @sshHelper?.execCommand "rm -rf ~/#{escapedPath}", (err, stdout, stderr) =>
      if err
        @socket.emit('delete', err.toString(), path)
        return
      @socket.emit('delete', null, path)

FSSocket.escape = (string) ->
  if typeof string == 'string'
    return "'" + string.replace(/'/g, "'\"'\"'") + "'"
  null

