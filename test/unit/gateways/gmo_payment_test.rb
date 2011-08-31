require 'test_helper'

class GmoPaymentTest < Test::Unit::TestCase
  def setup
    @gateway = GmoPaymentGateway.new(
                 :url => 'https://kt01.mul-pay.jp',
                 :site_id => 'site_id',
                 :site_pass => 'site_pass',
                 :shop_id => 'shop_id',
                 :shop_pass => 'shop_pass'
               )

    @credit_card = credit_card
    @amount = 100
    
    @options = { 
    }
  end
  
  def test_successful_purchase
    @gateway.expects(:ssl_post).times(2).returns(successful_entry_tran_response, successful_exec_tran_response)
    @options[:order_id] = "order_id"
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response

    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', response.authorization
  end
  
  def test_successful_purchase_with_member_registration
    @gateway.expects(:ssl_post).times(4).returns(successful_save_member_response, successful_save_card_response, successful_entry_tran_response, successful_exec_tran_response)
    @options[:order_id] = "order_id"
    @options[:store] = true
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', response.authorization
    assert_equal 'member_id:card_seq', response.params["billing_id"]
  end

  def test_successful_purchase_with_billing_id
    @gateway.expects(:ssl_post).times(2).returns(successful_entry_tran_response, successful_exec_tran_response)
    @options[:store] = true
    
    assert response = @gateway.purchase(@amount, "member_id:card_seq", @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', response.authorization
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).times(2).returns(successful_entry_tran_response, successful_exec_tran_response)
    @options[:order_id] = "order_id"
    
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', response.authorization
  end

  def test_successful_authorize_with_member_registration
    @gateway.expects(:ssl_post).times(4).returns(successful_save_member_response, successful_save_card_response, successful_entry_tran_response, successful_exec_tran_response)
    @options[:order_id] = "order_id"
    @options[:store] = true
    
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', response.authorization
    assert_equal 'member_id:card_seq', response.params["billing_id"]
  end

  def test_successful_authorize_with_billing_id
    @gateway.expects(:ssl_post).times(2).returns(successful_entry_tran_response, successful_exec_tran_response)
    @options[:store] = true
    
    assert response = @gateway.authorize(@amount, "member_id:card_seq", @options)
    assert_instance_of Response, response
    assert_success response
    
    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', response.authorization
  end

  def test_successful_capture
  end

  def test_successful_void
  end

  def test_successful_store
  end

  def test_successful_unstore
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(failed_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_failure response
  end

  # entry - exec(timeout) - exec(timeout) - exec(timeout) - search(timeout) - search(success) - void(timeout) - void(success)
  def test_timeout_purchase_void_success
    # tests the behaviour if the exec transactions succeeds but raises an timeout error on the client side
    @response_entry = stub(:code => 200, :message => 'OK', :body => successful_entry_tran_response)
    @response_search = stub(:code => 200, :message => 'OK', :body => successful_search_response)
    @response_void = stub(:code => 200, :message => 'OK', :body => successful_alter_tran_response)
    Net::HTTP.any_instance.expects(:post).times(8).returns(@response_entry).raises(Timeout::Error).raises(Timeout::Error).raises(Timeout::Error).raises(Timeout::Error).returns(@response_search).raises(Timeout::Error).returns(@response_void)
    @options[:order_id] = "order_id"
    
    exception = begin; @gateway.purchase(@amount, @credit_card, @options); rescue => e; e; end
  
    assert_raises(ActiveMerchant::ConnectionError) do
      raise exception if exception
    end
  
    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', exception.instance_variable_get("@authorization")
  end

  # entry - exec(timeout) - exec(success) - search(timeout) - search(success) - void(timeout) - void(timeout) - void(timeout)
  def test_timeout_purchase_void_timeout
    # tests the behaviour if the exec transactions succeeds but raises an timeout error on the client side
    @response_entry = stub(:code => 200, :message => 'OK', :body => successful_entry_tran_response)
    # @response_exec = stub(:code => 200, :message => 'OK', :body => unsuccessful_exec_tran_response)
    @response_search = stub(:code => 200, :message => 'OK', :body => successful_search_response)
    @response_void = stub(:code => 200, :message => 'OK', :body => successful_alter_tran_response)
    Net::HTTP.any_instance.expects(:post).times(9).returns(@response_entry).raises(Timeout::Error).raises(Timeout::Error).raises(Timeout::Error).raises(Timeout::Error).returns(@response_search).raises(Timeout::Error).raises(Timeout::Error).raises(Timeout::Error)
    @options[:order_id] = "order_id"
    
    exception = begin; @gateway.purchase(@amount, @credit_card, @options); rescue => e; e; end
  
    assert_raises(ActiveMerchant::ConnectionError) do
      raise exception if exception
    end

    # Replace with authorization number from the successful response
    assert_equal 'order_id:access_id:access_pass', exception.instance_variable_get("@authorization")
  end

  private
  
  # Place raw successful response from gateway here
  def successful_alter_tran_response
    "ErrCode=&ErrInfo=&AccessID=access_id&AccessPass=access_pass&Forward=forward&Approve=approve&TranID=tran_id&TranDate=tran_date"
  end

  def successful_search_response
    "OrderID=&Status=AUTH&ProcessDate=&JobCd=&AccessID=&AccessPass=&ItemCode&Amount=&Tax=&SiteID=&MemberID=&CardNo=&Expire=&Method=&PayTimes=&Forward&TranID=&Approve=&ClientField1=&ClientField2=&ClientField3"
  end

  def successful_delete_card_response
    "ErrCode=&ErrInfo=&CardSeq=card_seq"
  end

  def successful_delete_member_response
    "ErrCode=&ErrInfo=&MemberID=member_id"
  end
  
  def successful_entry_tran_response
    "ErrCode=&ErrInfo=&AccessID=access_id&AccessPass=access_pass"
  end
  
  def successful_exec_tran_response
    "ErrCode=&ErrInfo=&ACS=acs&OrderID=order_id&Forward=forward&Method=method&PayTimes=pay_times&Approve=approve&TranID=tran_id&TranDate=tran_date&CheckString=check_string&ClientField1=client_field_1&ClientField2=client_field_2&ClientField3=client_field_3"
  end

  def unsuccessful_exec_tran_response
    "ErrCode=E01&ErrInfo=E01050004"
  end
  
  def successful_save_card_response
    "ErrCode=&ErrInfo=&CardSeq=card_seq&CardNo=card_no&Forward=forward"
  end

  def successful_save_member_response
    "ErrCode=&ErrInfo=&MemberID=member_id"
  end
  
  # Place raw failed response from gateway here
  def failed_response
    "ErrCode=E01|E01|E01|E01|E01&ErrInfo=E01010001|E01020001|E01030002|E01040001|E01060001"
  end
end
