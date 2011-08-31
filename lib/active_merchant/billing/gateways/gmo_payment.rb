require 'pp'
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GmoPaymentGateway < Gateway
      self.class_attribute :timeout
      self.timeout = 10
      
      self.retry_safe = true
      
      # The format of the amounts used by the gateway
      # :dollars => '12.50'
      # :cents => '1250'
      self.money_format = :cents

      # The default currency for the transactions if no currency is provided
      self.default_currency = 'JPY'

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['JP']

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :jcb, :american_express]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.gmo-pg.com/'

      # The name of the gateway
      self.display_name = 'GMO Payment Gateway'

      SUCCESS_MESSAGE = "クレジットカードでの決済が成功しました。"
      FAILURE_MESSAGE = "クレジットカードでの決済に失敗しました。"
      FAILURE_MESSAGES = {
      "M01004014" => "指定されたオーダーIDの取引は、既に決済を依頼しています。",
      "E01010001" => "ショップIDが指定されていません。",
      "E01010008" => "ショップIDに半角英数字以外の文字が含まれているか、13文字を超えています。",
      "E01020008" => "ショップパスワードに半角英数字以外の文字が含まれているか、10文字を超えています。",
      "E01030002" => "指定されたIDとパスワードのショップが存在しません。",
      "E01040003" => "オーダーIDが最大文字数を超えています。",
      "E01040010" => "既にオーダーIDが存在しています。",
      "E01050001" => "処理区分が指定されていません。",
      "E01050004" => "指定した処理区分の処理は実行出来ません。",
      "E01060001" => "利用金額が指定されていません。",
      "E01060006" => "利用金額に数字以外の文字が含まれています。",
      "E01060010" => "取引の利用金額と指定した利用金額が一致していません。",
      "E01110002" => "指定されたIDとパスワードの取引が存在しません。",
      "E01170001" => "カード番号が指定されていません。",
      "E01180001" => "有効期限が指定されていません。",
      "E01190008" => "サイトIDの書式が正しくありません。",
      "E01200008" => "サイトパスワードの書式が正しくありません。",
      "E01210002" => "指定されたIDとパスワードのサイトが存在しません。",
      "E01240002" => "指定されたカードが存在しません。",
      "E01260010" => "指定された支払方法はご利用できません。",
      "E01260001" => "支払方法が指定されていません。",
      "E01390002" => "指定されたサイトIDと会員IDの会員が存在しません。",
      "E61010002" => "決済処理に失敗しました。申し訳ございませんが、しばらく時間をあけて購入画面からやり直してください。",
      "E92000001" => "只今、大変込み合っていますので、しばらく時間をあけて再度決済を行ってください。"
      }

      def initialize(options = {})
        requires!(options, :url, :site_id, :site_pass, :shop_id, :shop_pass)
        @options = options
        super
      end  

      def purchase(money, creditcard_or_billing_id, options = {})
        store_entry_exec money, creditcard_or_billing_id, (money == 0 ? :check : :capture), options
      end

      # authorizes or checks (if money == 0) a credit card
      def authorize(money, creditcard_or_billing_id, options = {})
        store_entry_exec money, creditcard_or_billing_id, (money == 0 ? :check : :auth), options
      end

      def capture(money, authorization, options = {})
        alter_tran money, authorization, :sales, options
      end

      def void(authorization, options = {})
        response = search_trade authorization, options
        return response unless response.success?

        status = response.params["Status"]
        process_date = Time.parse response.params["ProcessDate"]
        
        # use void for auth, elsewise use return
        job_cd ||= :void if status == "AUTH"
        job_cd ||= :return

        # use returnx if process_date is not in this month
        job_cd = :returnx if job_cd == :return && !(process_date.month == Time.now.month && process_date.year == Time.now.year)

        alter_tran nil, authorization, job_cd, options
      end

      def store(creditcard, options = {})
        # save member
        member_response = save_member options

        return member_response unless member_response.success?

        member_id = member_response.params["MemberID"]

        # save card
        exception = card_response = nil
        begin card_response = save_card member_id, creditcard, options; rescue ConnectionError => exception; end # catches timeout etc.

        unless exception.blank? && card_response.success?
          if exception
            exception.instance_variable_set "@billing_id", member_id
          end

          delete_member member_id, options
          raise exception if exception
          return card_response
        end

        card_response
      end

      def unstore(billing_id, options = {})
        delete_card billing_id, options
        delete_member billing_id, options
      end

private
      def store_entry_exec(money, creditcard_or_billing_id, job_cd, options = {})
        # store member if store option is given
        if options[:store]
          if creditcard_or_billing_id.is_a?(ActiveMerchant::Billing::CreditCard)
            # membership
            response = store creditcard_or_billing_id, options

            return response unless response.success?
            creditcard_or_billing_id = options[:billing_id] = response.params["billing_id"]
            options[:created_membership] = true
          else
            options[:billing_id] = creditcard_or_billing_id
          end
        end

        response = entry_tran(money, job_cd, options)

        unless response.success?
          unstore creditcard_or_billing_id, options if options[:created_membership]
          return response
        end

        authorization = response.authorization

        exception = response = nil
        begin response = exec_tran money, authorization, creditcard_or_billing_id, options; rescue ConnectionError => exception; end # catches timeout etc.

        unless exception.blank? && response.success?
          if exception
            exception.instance_variable_set "@billing_id", creditcard_or_billing_id if options[:created_membership]
            exception.instance_variable_set "@authorization", authorization
          end
                      
          # void the payment if the payment gateway has already the payment, ignore errors
          begin void authorization rescue ConnectionError; end

          # remove membership if failed, ignore errors
          unstore creditcard_or_billing_id, options rescue nil if options[:created_membership]

          raise exception if exception

          return response
        end

        response.params["billing_id"] = options[:billing_id] if options[:billing_id] && options[:created_membership]

        response
      end

      def alter_tran money, authorization, job_cd, options
        post = {}
        post[:in] = ["ShopID", "ShopPass", "AccessID", "AccessPass", "JobCd", "Amount"]
        post[:out] = ["AccessID", "AccessPass", "Forward", "Approve", "TranID", "TranDate"]

        add_shop post
        add_authorization post, authorization, options
        add_job_cd post, job_cd, /VOID|RETURN|RETURNX|CAPTURE|AUTH|SALES/
        add_amount post, money, options

        commit "/payment/AlterTran.idPass", post
      end

      def delete_card billing_id, options
        post = {}
        post[:in] = ["SiteID", "SitePass", "MemberID", "CardSeq"]
        post[:out] = ["CardSeq"]

        add_site post
        add_creditcard_or_billing_id post, billing_id, options

        commit "/payment/DeleteCard.idPass", post
      end

      def delete_member billing_id, options
        post = {}
        post[:in] = ["SiteID", "SitePass", "MemberID"]
        post[:out] = ["MemberID"]

        add_site post
        add_creditcard_or_billing_id post, billing_id, options

        commit "/payment/DeleteMember.idPass", post
      end

      def entry_tran money, job_cd, options
        post = {}
        post[:in] = ["ShopID", "ShopPass", "OrderID", "JobCd", "Amount", "Tax"]
        post[:out] = ["AccessID", "AccessPass"]

        add_shop post
        add_authorization post, nil, options
        add_job_cd post, job_cd, /(CHECK|CAPTURE|AUTH|SAUTH)/
        add_amount post, money, options

        commit "/payment/EntryTran.idPass", post
      end

      def exec_tran money, authorization, creditcard_or_billing_id, options
        #access_id, access_pass, order_id, card_no=nil, expire=nil, member_id=nil, card_seq=nil, custom1=nil, custom2=nil, custom3=nil
        post = {}

        add_site post
        add_authorization post, authorization, options
        add_creditcard_or_billing_id post, creditcard_or_billing_id, options
        add_custom post, options

        post["Method"] = "1" # 一括

        if post["MemberID"].blank?
          post[:in] = ["AccessID", "AccessPass", "OrderID", "Method", "CardNo", "Expire", "SecurityCode", "SiteID", "SitePass", "ClientField1", "ClientField2", "ClientField3"]
        else
          post[:in] = ["AccessID", "AccessPass", "OrderID", "Method", "SiteID", "SitePass", "MemberID", "CardSeq", "ClientField1", "ClientField2", "ClientField3"]
        end
        post[:out] = ["ACS", "OrderID", "Forward", "Method", "PayTimes", "Approve", "TranID", "TranDate", "CheckString"]

        commit "/payment/ExecTran.idPass", post
      end

      def save_card billing_id, creditcard, options
        post = {}
        post[:in] = ["SiteID", "SitePass", "MemberID", "CardNo", "Expire"]
        post[:out] = ["CardSeq", "CardNo", "Forward"]

        options[:billing_id] = billing_id

        add_site post
        add_creditcard_or_billing_id post, creditcard, options

        commit "/payment/SaveCard.idPass", post
      end

      def save_member options
        post = {}
        post[:in] = ["SiteID", "SitePass", "MemberID", "MemberName"]
        post[:out] = ["MemberID"]

        add_site post
        add_creditcard_or_billing_id post, create_member_id, options

        commit "/payment/SaveMember.idPass", post
      end

      def search_trade authorization, options
        post = {}
        post[:in] = ["ShopID", "ShopPass", "OrderID"]
        post[:out] = ["OrderID", "Status", "ProcessDate", "JobCd", "AccessID", "AccessPass", "ItemCode", 
          "Amount", "Tax", "SiteID", "MemberID", "CardNo", "Expire", "Method", "PayTimes", "Forward", 
          "TranID", "Approve", "ClientField1", "ClientField2", "ClientField3"]

        add_shop post
        add_authorization post, authorization, options

        commit "/payment/SearchTrade.idPass", post
      end

      # "OrderID", "AccessID", "AccessPass"
      def add_authorization(post, authorization, options)
        post["OrderID"], post["AccessID"], post["AccessPass"] = authorization.to_s.split(":")
        post["OrderID"] = options[:order_id] || create_order_id if post["OrderID"].blank?
      end

      def add_job_cd(post, job_cd, regex)
        job_cd = job_cd.to_s.upcase
        raise "unknown job_cd #{job_cd}" unless regex.match job_cd

        post["JobCd"] = job_cd
      end

      def add_amount(post, money, options)
        return if money.blank? # for voids
        
        post["Tax"] = options[:tax].to_s
        post["Amount"] = (money.to_s.to_i - options[:tax].to_s.to_i).to_s
      end

      def add_custom(post, options)
        post["ClientField1"] = options[:description] || options[:custom1]
        post["ClientField2"] = options[:custom2]
        post["ClientField3"] = options[:custom3]
      end

      #MemberName
      def add_creditcard_or_billing_id(post, creditcard_or_billing_id, options)
        card = billing_id = nil

        if creditcard_or_billing_id.is_a?(ActiveMerchant::Billing::CreditCard)
          card = creditcard_or_billing_id
        else
          billing_id = creditcard_or_billing_id
        end

        billing_id ||= options[:billing_id] if options[:billing_id]

        post["MemberID"], post["CardSeq"] = billing_id.split(":") if billing_id
        post["CardNo"], post["Expire"], post["SecurityCode"] = card.number, expdate(card), card.verification_value if card
      end

      def add_shop post
        post["ShopID"] = @options[:shop_id]
        post["ShopPass"] = @options[:shop_pass]
      end

      def add_site post
        post["SiteID"] = @options[:site_id]
        post["SitePass"] = @options[:site_pass]
      end

      def create_order_id
        # creates 27 random digits
        ActiveSupport::SecureRandom.hex(9).scan(/\w\w/).map{|n| '%03d' % n.to_i(16) }.join
      end
      
      def create_member_id
        create_order_id
      end

      def commit(action, parameters)
        output_params = parameters.delete :out
        input_params = parameters.delete :in

        # add error output parameters
        # output_params += ["ErrCode", "ErrInfo"]

        # remove extra parameters
        parameters.reject!{|key,value|value.blank?}
        all_info = parameters.dup
        parameters.reject!{|key,value|!input_params.include?(key)}

        # send and parse the request
        response = parse(ssl_post((test? ? "https://kt01.mul-pay.jp" : @options[:url]) + action, post_data(parameters)))
        
        # merge response
        all_info.merge!(response)

        if all_info.include?("MemberID") && all_info.include?("CardSeq")
          response["billing_id"] = "#{all_info["MemberID"]}:#{all_info["CardSeq"]}"
        end

        if all_info.include?("OrderID") && all_info.include?("AccessID") && all_info.include?("AccessPass")
          authorization = "#{all_info["OrderID"]}:#{all_info["AccessID"]}:#{all_info["AccessPass"]}"
        end

        invalid_output = output_params - response.keys
        if success?(response) && !invalid_output.empty?
          raise "DID NOT GET EXPECTED RESPONSE PARAMETERS. got <#{response.keys.inspect}> expected <#{output_params.inspect}> still required <#{invalid_output.inspect}>"
        end

        Response.new(success?(response), message_from(response), response, 
          :test => test?,
          :authorization => authorization
        )
      end

      def post_data(parameters = {})
        parameters.collect{|key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end

      def parse(body)
        hash = CGI::parse(body)
        hash.each{|k,v|hash[k] = v ? CGI.unescape(v.join) : nil}
        hash
      end     

      def success?(response)
        !response.empty? && response["ErrCode"].empty? && response["ErrInfo"].empty?
      end

      def message_from(response)
        return SUCCESS_MESSAGE if success?(response)

        Hash[[response["ErrCode"].split("|"), response["ErrInfo"].split("|")].transpose].collect do |code, info|
          "#{FAILURE_MESSAGES[info] || FAILURE_MESSAGE} (#{code}-#{info})"
        end.join(", ")
      end

      # Return the expiry for the given creditcard in the required
      # format for a command.
      def expdate(credit_card)
        month = format(credit_card.month, :two_digits)
        year  = format((credit_card.year > 2000 ? credit_card.year - 2000 : credit_card.year), :two_digits)
        "#{year}#{month}"
      end
    end
  end
end
