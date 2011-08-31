require 'test_helper'

class RemoteGmoPaymentTest < Test::Unit::TestCase
  

  def setup
    @gateway = GmoPaymentGateway.new(fixtures(:gmo_payment))
    
    @amount = 100
    @credit_card = credit_card('4111111111111111')
    @declined_card = credit_card('4999000000000002')
    
    @options = { 
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'クレジットカードでの決済が成功しました。', response.message
    assert response.authorization

    assert status = @gateway.send(:search_trade, response.authorization, {})
    assert_success status
    assert_equal 'CAPTURE', status.params["Status"]
  end

  def test_successful_purchase_and_void
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'クレジットカードでの決済が成功しました。', response.message
    assert response.authorization

    assert void = @gateway.void(response.authorization)
    assert_success void

    assert status = @gateway.send(:search_trade, response.authorization, {})
    assert_success status
    assert_equal 'RETURN', status.params["Status"]
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'クレジットカードでの決済に失敗しました。 (G02-42G020000)', response.message
  end

  def test_unsuccessful_authorize
    assert response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'クレジットカードでの決済に失敗しました。 (G02-42G020000)', response.message
  end

  def test_authorize_and_capture
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal 'クレジットカードでの決済が成功しました。', auth.message
    assert auth.authorization

    assert capture = @gateway.capture(amount, auth.authorization)
    assert_success capture

    assert status = @gateway.send(:search_trade, auth.authorization, {})
    assert_success status
    assert_equal 'SALES', status.params["Status"]
  end

  def test_authorize_and_void
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal 'クレジットカードでの決済が成功しました。', auth.message
    assert auth.authorization

    assert void = @gateway.void(auth.authorization)
    assert_success void

    assert status = @gateway.send(:search_trade, auth.authorization, {})
    assert_success status
    assert_equal 'VOID', status.params["Status"]
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, 'abc')
    assert_failure response
    assert_equal '指定されたIDとパスワードの取引が存在しません。 (E01-E01110002)', response.message
  end

  # NOTE: Test PG seems not to check the site id and pass
  # def test_invalid_site_id
  #   gateway = GmoPaymentGateway.new fixtures(:gmo_payment).merge(
  #               :site_id => 'xxx',
  #               :site_pass => 'yyy'
  #             )
  #   assert response = gateway.purchase(@amount, @credit_card, @options)
  #   assert_failure response
  #   assert_equal '指定されたIDとパスワードのサイトが存在しません。 (E01-E01210002)', response.message
  # end

  def test_invalid_shop_id
    gateway = GmoPaymentGateway.new fixtures(:gmo_payment).merge(
                :shop_id => 'xxx',
                :shop_pass => 'yyy'
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal '指定されたIDとパスワードのショップが存在しません。 (E01-E01030002)', response.message
  end
end
