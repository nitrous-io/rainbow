fs = require 'fs'
tmp = require 'tmp'
childProcess = require 'child_process'

module.exports = class SSHHelper
  constructor: (@user, @host, @port, @key) ->

  writeKeyFile: (callback) -> # callback(err, sshArgs, deleteKeyFile)
    tmp.file (err, path, fd) =>
      if err
        callback(err)
        return
      b = new Buffer(@key)
      fs.write fd, b, 0, b.length, 0, (err, written, buffer) =>
        if err
          fs.unlink path, -> callback(err)
          return
        sshArgs = [
          '-i', path
          '-o', 'UserKnownHostsFile=/dev/null'
          '-o', 'StrictHostKeyChecking=no'
          '-o', 'PubkeyAuthentication=yes'
          '-o', 'PasswordAuthentication=no'
          '-o', 'LogLevel=FATAL'
          '-p', "#{@port}"
          "#{@user}@#{@host}"
        ]
        deleteKeyFile = (callback) ->
          fs.unlink path, ->
            callback?()
        callback(null, sshArgs, deleteKeyFile)

  execCommand: (command, callback) -> # callback(err, stdout, stderr)
    this.writeKeyFile (err, sshArgs, deleteKeyFile) ->
      if err
        callback(err)
        return
      sshArgs.push("export LC_ALL=en_US.UTF-8; #{command}")
      try
        childProcess.execFile '/usr/bin/ssh', sshArgs, timeout: 20000, (err, stdout, stderr) ->
          deleteKeyFile ->
            callback(err, stdout, stderr)
      catch err
        deleteKeyFile ->
          callback(err)

