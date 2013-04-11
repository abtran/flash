package com.pubnub.operation{
import com.pubnub.PnUtils;
import com.pubnub.Settings;

import flash.net.URLRequest;

//import com.pubnub.net.URLRequest;
	
	/**
	 * ...
	 * @author firsoff maxim, firsoffmaxim@gmail.com, icq : 235859730
	 */
	public class SubscribeOperation extends Operation{
		
		public function SubscribeOperation(origin:String, timeout:uint = Settings.SUBSCRIBE_OPERATION_TIMEOUT) {
			super(origin, timeout);
		}
		
		override public function setURL(url:String = null, args:Object = null):URLRequest{
			//https://pubsub.pubnub.com/subscribe/demo/my_channel/0/13552888637749400?uuid=6240373A-0FC0-5FF5-0D96-A349958DD417
			var channel:String = args.channel;
			var uid:String = args.uid;
			var subscribeKey:String = args.subscribeKey;
			var timetoken:String = args.timetoken;
			url = _origin + "/" + "subscribe" + "/" + subscribeKey + "/" + PnUtils.encode(channel) + "/" + 0 + '/' + timetoken;
			url += '?uuid=' + uid;
			return super.setURL(url, args);
		}
	}
}