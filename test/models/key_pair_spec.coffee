KeyPair = require '../../app/models/key_pair'
BaseModel = require('action-base').BaseModel
actionCipher = require('action-base').actionCipher
app = require '../../app'

describe 'KeyPair', ->
  it 'is a subclass of BaseModel', ->
    expect(new KeyPair).to.be.an.instanceof BaseModel

  its 'tableName property is defined', ->
    expect(KeyPair.tableName).to.equal 'key_pairs'

  describe '#get private_key', ->
    keyPair = null

    beforeEach ->
      unless key = app.settings.aesKey
        throw new Error 'AES_KEY not defined!'
      keyPair = new KeyPair
      [iv, encryptedPrivateKey] = actionCipher.encrypt key, 'seriously proprietary and confidential private key'
      keyPair.encrypted_private_key = encryptedPrivateKey
      keyPair.encrypted_private_key_iv = iv

    it 'decrypts and returns private_key', ->
      expect(keyPair.private_key).to.equal 'seriously proprietary and confidential private key'

