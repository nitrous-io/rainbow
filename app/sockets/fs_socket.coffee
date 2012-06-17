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

  onList: (path, cid) =>
    @sshHelper?.execCommand "ls -1bp ~/#{FSSocket.escape(path)}", (err, stdout, stderr) =>
      if err
        @socket.emit('list', err.toString(), path, cid)
        return
      stdout = stdout.trim()

      files = if stdout.length == 0
        []
      else
        stdout.replace(/\\ /g, ' ').split("\n")

      files = _.filter(files, (file) -> file.indexOf("\\") == -1)
      @socket.emit('list', null, path, cid, files)

  onNew: (path, cid) =>
    if path.match /\/$/
      cmd = "mkdir -p ~/#{FSSocket.escape(path)}"
    else
      cmd = "touch ~/#{FSSocket.escape(path)}"
    @sshHelper?.execCommand cmd, (err, stdout, stderr) =>
      if err
        @socket.emit('new', err.toString(), path, cid)
        return
      @socket.emit('new', null, path, cid)

  onRead: (path, cid) =>
    escapedPath = FSSocket.escape(path)
    @sshHelper?.execCommand "(file ~/#{escapedPath} | grep -q 'empty\\|text') && (cat ~/#{escapedPath})", (err, stdout, stderr) =>
      if err
        @socket.emit('read', err.toString(), path, cid)
        return
      @socket.emit('read', null, path, cid, stdout.slice(0, -1))

  onWrite: (path, cid, data) =>
    @sshHelper?.execCommand "echo -e #{FSSocket.escape(data)} > ~/#{FSSocket.escape(path)}", (err, stdout, stderr) =>
      if err
        @socket.emit('write', err.toString(), path, cid)
        return
      @socket.emit('write', null, path, cid)

  onDelete: (path, cid) =>
    @sshHelper?.execCommand "rm -rf ~/#{FSSocket.escape(path)}", (err, stdout, stderr) =>
      if err
        @socket.emit('delete', err.toString(), path, cid)
        return
      @socket.emit('delete', null, path, cid)

FSSocket.escape = (string) ->
  if typeof string == 'string'
    return "'" + string.replace(/'/g, "'\"'\"'") + "'"
  null

