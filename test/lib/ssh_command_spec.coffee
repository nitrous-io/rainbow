SSHCommand = require '../../app/lib/ssh_command'
fs = require 'fs'
tmp = require 'tmp'
childProcess = require 'child_process'

describe 'SSHCommand', ->
  sshCommand = null

  beforeEach ->
    sshCommand = new SSHCommand('peter', 'localhost', '2222', 'ssh-rsa AAAB3NzaC1yc2EAAA peter@kim')

  describe '#exec', ->
    tmpFileStub = err = cbSpy = null

    context 'when temp file failed to get created', ->
      beforeEach ->
        err = new Error
        tmpFileStub = sinon.stub tmp, 'file', (cb) ->
          cb(err)
        cbSpy = sinon.spy()
        sshCommand.exec('ls', cbSpy)

      afterEach ->
        tmpFileStub.restore()

      it 'makes a callback with the error', ->
        cbSpy.calledWith(err).should.be.true

    context 'when temp file is successfully created', ->
      fakeFd = fsWriteStub = fsUnlinkStub = null

      beforeEach ->
        err = new Error
        fakeFd = {}
        tmpFileStub = sinon.stub tmp, 'file', (cb) ->
          cb(null, '/tmp/tmpfile', fakeFd)
        fsUnlinkStub = sinon.stub fs, 'unlink', (path, cb) ->
          cb()

      afterEach ->
        tmpFileStub.restore()
        fsUnlinkStub.restore()

      context 'when the key failed to be written to the temp file', ->
        beforeEach ->
          fsWriteStub = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            fd.should.equal fakeFd
            cb(err)
          cbSpy = sinon.spy()
          sshCommand.exec('ls', cbSpy)
          fsWriteStub.called.should.be.true

        afterEach ->
          fsWriteStub.restore()

        it 'deletes the temp file', ->
          fsUnlinkStub.called.should.be.true
          fsUnlinkStub.args[0][0].should.equal '/tmp/tmpfile'

        it 'makes a callback with the error', ->
          cbSpy.calledWith(err).should.be.true

      context 'when the key is successfully written to the temp file', ->
        cpExecFileStub = null

        beforeEach ->
          fsWriteStub = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            fd.should.equal fakeFd
            cb()
          cpExecFileStub = sinon.stub childProcess, 'execFile', (file, args, opts, cb) ->
            cb(err, 'fake stdout', 'fake stderr')
          cbSpy = sinon.spy()
          sshCommand.exec('ls', cbSpy)
          fsWriteStub.called.should.be.true

        afterEach ->
          fsWriteStub.restore()
          cpExecFileStub.restore()

        it 'executes a given command', ->
          cpExecFileStub.called.should.be.true
          cpExecFileStub.args[0][0].should.equal '/usr/bin/env'
          cmdArgs = cpExecFileStub.args[0][1].join(' ')
          cmdArgs.should.match /^ssh /
          cmdArgs.should.match /-i \/tmp\/tmpfile/
          cmdArgs.should.match /-o UserKnownHostsFile=\/dev\/null/
          cmdArgs.should.match /-o StrictHostKeyChecking=no/
          cmdArgs.should.match /-o PubkeyAuthentication=yes/
          cmdArgs.should.match /-o PasswordAuthentication=no/
          cmdArgs.should.match /-p 2222/
          cmdArgs.should.match /peter@localhost/
          cmdArgs.should.match /ls/
          cpExecFileStub.args[0][2].should.eql { timeout: 20000 }

        it 'deletes the temp file', ->
          fsUnlinkStub.called.should.be.true
          fsUnlinkStub.args[0][0].should.equal '/tmp/tmpfile'

        it 'makes a callback with given err, stdout, and stderr', ->
          cbSpy.calledWith(err, 'fake stdout', 'fake stderr').should.be.true

