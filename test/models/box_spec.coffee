Box = require '../../app/models/box'
BaseModel = require '../../app/models/base_model'
KeyPair = require '../../app/models/key_pair'

describe 'Box', ->
  it 'is a subclass of BaseModel', ->
    (new Box).should.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    Box.tableName.should.equal 'boxes'

  describe '#findKeyPair', ->
    box = cbSpy = null

    beforeEach ->
      box = new Box(id: 123)
      sinon.stub KeyPair, 'findOne'
      cbSpy = sinon.spy()

    afterEach ->
      KeyPair.findOne.restore()

    it 'finds a key pair object for this box', ->
      box.findKeyPair(cbSpy)
      KeyPair.findOne.calledWith('box_id = $1', [123], cbSpy).should.be.true

