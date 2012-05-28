KeyPair = require '../../app/models/key_pair'
BaseModel = require '../../app/models/base_model'

describe 'KeyPair', ->
  it 'is a subclass of BaseModel', ->
    (new KeyPair).should.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    KeyPair.tableName.should.equal 'key_pairs'

