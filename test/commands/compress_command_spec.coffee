CompressCommand = require '../../app/commands/compress_command'

describe 'CompressCommand', ->
  command = sendSpy = null

  beforeEach ->
    sendSpy = sinon.spy()
    command = new CompressCommand 'some/path/project', sendSpy

  describe '#commandArguments', ->
    args = null

    beforeEach ->
      args = command.commandArguments()

    it 'sets modifiers for zip command', ->
      expect(args).to.contain '-9'
      expect(args).to.contain '-r'
      expect(args).to.contain '-q'

    it 'has the file path and directory to extract', ->
      expect(args.slice(-2)).to.deep.equal ['/tmp/project', '/home/action/some/path/project']

  describe '#detectErrors', ->
    it 'detects cannot create output file error', ->
      sampleErr = "zip error: Could not create output file\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.cannotCreateOutputFile

    it 'detects no directory to compress error', ->
      sampleErr = "zip error: Nothing to do!\n"
      expect(command.detectErrors(sampleErr)).to.eq command.errorSlugs.noDirectoryToCompress
