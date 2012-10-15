KeyPair = require '../../app/models/key_pair'
BaseModel = require('action-base').BaseModel

describe 'KeyPair', ->
  it 'is a subclass of BaseModel', ->
    expect(new KeyPair).to.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    expect(KeyPair.tableName).to.equal 'key_pairs'

