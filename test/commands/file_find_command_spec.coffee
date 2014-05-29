actionBase = require 'action-base'
app = require '../../app'
FileFindCommand = require '../../app/commands/file_find_command'

describe 'FileFindCommand', ->
  command = sendSpy = null

  beforeEach ->
    sendSpy = sinon.spy()
    command = new FileFindCommand 'term', 'location', sendSpy

  describe '#commandArguments', ->
    args = null

    beforeEach ->
      args = command.commandArguments()

    it 'has term and location', ->
      expect(args).to.deep.equal ['-i', '-g', '.*?t.*?e.*?r.*?m.*?', 'location']

  describe '#detectErrors', ->
    it 'detects path not found error', ->
      sampleErr = "ERR: Error stat()ing: werkspice\nERR: Error opening directory werkspice: No such file or directory\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.pathNotFound

    it 'detects binary not found error', ->
      sampleErr = "/usr/local/bin/matcher: not found"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.noBinary
