package com.pubnub {
	
	import com.pubnub.connection.*;
	import com.pubnub.environment.*;
	import com.pubnub.log.*;
	import com.pubnub.net.*;
	import com.pubnub.operation.*;
	import com.pubnub.subscribe.*;
	import flash.errors.*;
	import flash.events.*;
	import flash.system.Security;
	import flash.utils.*;
	use namespace pn_internal;
	
	[Event(name="initError", type="com.pubnub.PnEvent")]
	[Event(name="init", type="com.pubnub.PnEvent")]
	public class Pn extends EventDispatcher {
		static private var __instance:Pn;

		private var _initialized:Boolean = false;
		
        private var subscribeConnection:Subscribe;
		
		private var _origin:String;
		private var _ssl:Boolean;
		private var _publishKey:String = "demo";
		private var _subscribeKey:String = "demo";
		private var secretKey:String = "";
		private var cipherKey:String = "";

        private var _sessionUUID:String = "";
		private var environment:Environment;
		
		static pn_internal var syncConnection:SyncConnection;
		
		public function Pn() {
			if (__instance) throw new IllegalOperationError('Use [Pn.instance] getter');
			setup();
		}
		
		private function setup():void {

			syncConnection = new SyncConnection(Settings.OPERATION_TIMEOUT);
			
			environment = new Environment(origin);
			environment.addEventListener(EnvironmentEvent.SHUTDOWN, onEnvironmentShutdown);

            environment.addEventListener(NetMonEvent.HTTP_DISABLE_VIA_SUBSCRIBE_TIMEOUT, onEnvironmentHttpDisable);
            environment.addEventListener(NetMonEvent.HTTP_ENABLE_VIA_SUBSCRIBE_TIMEOUT, onEnvironmentHttpEnable);
		}
		
		private function onEnvironmentHttpDisable(e:NetMonEvent):void {
            Log.log("Disabling network due to subscribe timeout", Log.DEBUG, new Operation("Aux Ping"));
			if (subscribeConnection) {
				subscribeConnection.networkEnabled = false;
			}
			dispatchEvent(e);
		}
		
		private function onEnvironmentHttpEnable(e:NetMonEvent):void {
            syncConnection.networkEnabled = true;

            if (subscribeConnection) {
                subscribeConnection.retryMode = false;
                subscribeConnection.retryCount = 0;
				subscribeConnection.networkEnabled = true;
			}
			
			if (_initialized == false) {
                startEnvironment();
			}
			dispatchEvent(e);
		}
		
		private function onEnvironmentShutdown(e:EnvironmentEvent):void {
			shutdown(Errors.NETWORK_LOST);
		}
		
		private function shutdown(reason:String = ''):void {
			// define last params
			var channels:String = 'no channels';
			var lastToken:String = null;
			if (subscribeConnection) {
				if (subscribeConnection.channels) {
					channels = subscribeConnection.channels.join(',');
				}
				lastToken = subscribeConnection.lastToken;
			}
			syncConnection.close();
			if (subscribeConnection) subscribeConnection.close();
			environment.stop();
			_initialized = false;
			Log.log('Shutdown', Log.WARNING);
			
			dispatchEvent(new NetMonEvent(NetMonEvent.HTTP_DISABLE));
			dispatchEvent(new EnvironmentEvent(EnvironmentEvent.SHUTDOWN, null, [0, reason, channels, lastToken]));
		}
		

		
		public static  function get instance():Pn {
			__instance ||= new Pn();
			return __instance;
		}
		
		public static function  init(config:Object):void {
			instance.init(config);
		}
		
		/*------------------- INIT --------------------------------*/
		public function init(config:Object):void {
			if (_initialized) {
				shutdown('reinitializing');
			}
			_initialized = false;
			initKeys(config);
            _sessionUUID ||= PnUtils.getUID();

			//start Environment service (wait first HTTP_ENABLE event)
			environment.start();
			
			subscribeConnection ||= new Subscribe();

            if (subscribeConnection) {
                subscribeConnection.UUID = _sessionUUID;
            }
            subscribeConnection.addEventListener(SubscribeEvent.CONNECT, 	onSubscribe);
			subscribeConnection.addEventListener(SubscribeEvent.DATA, 		onSubscribe);
			subscribeConnection.addEventListener(SubscribeEvent.DISCONNECT, onSubscribe);
			subscribeConnection.addEventListener(SubscribeEvent.ERROR, 		onSubscribe);
            subscribeConnection.addEventListener(SubscribeEvent.WARNING, 	onSubscribe);
			subscribeConnection.addEventListener(SubscribeEvent.PRESENCE, 	onSubscribe);
			subscribeConnection.origin = _origin;
			subscribeConnection.subscribeKey = _subscribeKey;
			subscribeConnection.UUID = _sessionUUID;
			subscribeConnection.cipherKey = cipherKey;
			
            subscribeConnection.addEventListener(NetMonEvent.HTTP_DISABLE_VIA_SUBSCRIBE_TIMEOUT, delayedSubscribeRetry);
		}

        private function delayedSubscribeRetry(e:NetMonEvent):void {
            trace("Running onSubscribeTimeout in: " + Settings.RECONNECT_RETRY_DELAY);
            setTimeout(onSubscribeTimeout, Settings.RECONNECT_RETRY_DELAY, e);
        }

		private function onSubscribeTimeout(e:NetMonEvent):void {

            Log.log("Retrying " + subscribeConnection.retryCount + " / " + Settings.MAX_RECONNECT_RETRIES, Log.DEBUG, new SubscribeOperation("1"))

            if (subscribeConnection) {
				subscribeConnection.networkEnabled = false;
                subscribeConnection.retryMode = true;
                subscribeConnection.retryCount++;
            }

            // try to turn it back on
            if (subscribeConnection.retryCount < Settings.MAX_RECONNECT_RETRIES) {
                subscribeConnection.networkEnabled = true;
                //subscribeConnection.saveChannelsAndSubscribe();
                dispatchEvent(e);
            } else {
                dispatchEvent(new EnvironmentEvent(EnvironmentEvent.SHUTDOWN, Errors.NETWORK_RECONNECT_MAX_RETRIES_EXCEEDED));
            }

		}

		private function startEnvironment():void {
			_initialized = true;
			environment.start();
			dispatchEvent(new PnEvent(PnEvent.INIT,  "Init Completed"));
		}
		
		private function onInitError(event:OperationEvent):void {
			dispatchEvent(new PnEvent(PnEvent.INIT_ERROR, Errors.INIT_OPERATION_ERROR));
		}
		/*---------------SUBSCRIBE---------------*/
		public static function subscribe(channel:String, token:String = null):void{
            Pn.__instance.subscribeConnection.subscribe(channel, token);

        }
		
		/**
		 * 
		 * @param	channel for MX subcribe use "ch1,ch2,ch3,ch4"
		 */

		private function onSubscribe(e:SubscribeEvent):void {
			var subscribe:Subscribe = e.target as Subscribe;
			var status:String;

            trace(e.type);

            switch (e.type) {
				case SubscribeEvent.CONNECT:
					status = OperationStatus.CONNECT;

                    //subscribe.networkEnabled = true;
				break;
			
				case SubscribeEvent.DATA:

                    if (subscribeConnection.retryMode == true) {
                        Log.log("Recovering from Subscribe Timeout", Log.DEBUG, new Operation("Aux Ping"));
                        subscribeConnection.retryMode = false;
                        subscribeConnection.networkEnabled = true;

                        dispatchEvent(new NetMonEvent(NetMonEvent.HTTP_ENABLE_VIA_SUBSCRIBE_TIMEOUT));
                    }


                    status = OperationStatus.DATA;
				break;
				
				case SubscribeEvent.DISCONNECT:
					status = OperationStatus.DISCONNECT;
				break;
				
				case SubscribeEvent.PRESENCE:
					status = OperationStatus.DISCONNECT;
					dispatchEvent(new PnEvent(PnEvent.PRESENCE, e.data, e.data.channel));
					return;
				break;

                case SubscribeEvent.WARNING:
                    status = OperationStatus.WARNING;
                break;

				default: status = OperationStatus.ERROR;		
			}
			dispatchEvent(new PnEvent(PnEvent.SUBSCRIBE, e.data, e.data.channel, status));
		}
		
		/*---------------UNSUBSCRIBE---------------*/
		public static function unsubscribe(channel:String):void {             
			instance.unsubscribe(channel);
		}

		public function unsubscribe(channel:String):void {
			subscribeConnection.unsubscribe(channel);
		}
		
		public static function unsubscribeAll():void {
			instance.unsubscribeAll();
		}
		
		public function unsubscribeAll():void {
			if(subscribeConnection) subscribeConnection.unsubscribeAll();
		}
		
		/*---------------DETAILED HISTORY---------------*/
		public function detailedHistory(args:Object):void {
			var channel:String = args.channel;
			var sub_key:String = args['sub-key'];
			if (channel == null || 
				channel.length == 0 ||
				sub_key == null || 
				sub_key.length == 0) {
				dispatchEvent(new PnEvent(PnEvent.DETAILED_HISTORY, [ -1, 'Channel and subKey are missing'], channel, OperationStatus.ERROR));
				return;
			}
			var operation:Operation = createDetailedHistoryOperation(args);
			syncConnection.executeGet(operation);
		}
		
		private function onHistoryResult(e:OperationEvent):void {
			var pnEvent:PnEvent = new PnEvent(PnEvent.DETAILED_HISTORY, e.data, e.target.channel, OperationStatus.DATA);
			pnEvent.operation = e.target as Operation;
			dispatchEvent(pnEvent);
		}
		
		private function onHistoryFault(e:OperationEvent):void {
			var pnEvent:PnEvent = new PnEvent(PnEvent.DETAILED_HISTORY, e.data, e.target.channel, OperationStatus.ERROR);
			pnEvent.operation = e.target as Operation;
			dispatchEvent(pnEvent);
		}
		
		private function createDetailedHistoryOperation(args:Object = null):Operation{
			var history:HistoryOperation = new HistoryOperation(origin);
			history.cipherKey = cipherKey;
			history.setURL(null, args);
			history.addEventListener(OperationEvent.RESULT, onHistoryResult);
			history.addEventListener(OperationEvent.FAULT, onHistoryFault);
			return history;
		}
		
		/*---------------PUBLISH---------------*/
		public static function publish(args:Object):void {
			instance.publish(args);
		}
		
		public function publish(args:Object):void {
			var operation:Operation = createPublishOperation(args)
			syncConnection.executeGet(operation);
		}
		
		private function onPublishFault(e:OperationEvent):void {
			//trace('onPublishFault : ' + e.target.url);
			var pnEvent:PnEvent = new PnEvent(PnEvent.PUBLISH, e.data, e.target.channel, OperationStatus.ERROR);
			pnEvent.operation = e.target as Operation;
			dispatchEvent(pnEvent);
		}
		
		private function onPublishResult(e:OperationEvent):void {
			var pnEvent:PnEvent = new PnEvent(PnEvent.PUBLISH, e.data, e.target.channel, OperationStatus.DATA);
			pnEvent.operation = e.target as Operation;
			dispatchEvent(pnEvent);
		}
		
		private function createPublishOperation(args:Object = null):Operation{
			var publish:PublishOperation = new PublishOperation(origin);
			publish.cipherKey = cipherKey;
			publish.secretKey = secretKey;
			publish.publishKey = _publishKey;
			publish.subscribeKey = _subscribeKey;
			publish.setURL(null, args);
			publish.addEventListener(OperationEvent.RESULT, onPublishResult);
			publish.addEventListener(OperationEvent.FAULT, onPublishFault);
			return publish;
		}
		
		
		/*---------------TIME---------------*/
		public static function time():void {
			instance.time();
		}
		
		public function time():void {
			//throwInit();
			var operation:Operation = createTimeOperation();
			operation.addEventListener(OperationEvent.RESULT, onTimeResult);
			operation.addEventListener(OperationEvent.FAULT, onTimeFault);
			syncConnection.executeGet(operation);
		}
		
		private function onTimeFault(e:OperationEvent):void {
			var pnEvent:PnEvent = new PnEvent(PnEvent.TIME, e.data, null, OperationStatus.ERROR);
			dispatchEvent(pnEvent);
		}
		
		private function onTimeResult(e:OperationEvent):void {
			var pnEvent:PnEvent = new PnEvent(PnEvent.TIME, e.data, null, OperationStatus.DATA);
			dispatchEvent(pnEvent);
		}
		
		private function createTimeOperation(args:Object = null):Operation{
			var time:TimeOperation = new TimeOperation(origin);
			time.addEventListener(OperationEvent.RESULT, onTimeResult);
			time.addEventListener(OperationEvent.FAULT, onTimeFault);
			time.setURL();
			return time;
		}
		
		public static function getSubscribeChannels():Array{
			if (instance.subscribeConnection) {
				return instance.subscribeConnection.channels;
			}else {
				return null;
			}
		}
		
		private function initKeys(config:Object):void {
			_ssl = config.ssl;
			origin = config.origin;
			//trace('origin : ' + origin);
			if(config.publish_key)
				_publishKey = config.publish_key;
			
			if(config.sub_key)
				_subscribeKey = config.sub_key;
			
			if(config.secret_key)
				secretKey = config.secret_key;
			
			if(config.cipher_key)
				cipherKey = config.cipher_key;
		}

		public function destroy():void {
			shutdown();
			
			syncConnection.destroy();
			syncConnection = null;
			
			subscribeConnection.destroy();
			subscribeConnection = null;
			
			environment.destroy();
			environment.removeEventListener(EnvironmentEvent.SHUTDOWN, 		onEnvironmentShutdown);
			environment.removeEventListener(EnvironmentEvent.RECONNECT, 	onEnvironmentHttpEnable);
			environment.removeEventListener(NetMonEvent.HTTP_DISABLE, 		onEnvironmentHttpDisable);
			environment = null;
			
			subscribeConnection = null;
			_initialized = false;
			__instance = null;
		}
		
		public function get sessionUUID():String {
			return _sessionUUID;
		}
		
		public function get publishKey():String {
			return _publishKey;
		}
		
		public function get subscribeKey():String {
			return _subscribeKey;
		}
		
		public function get initialized():Boolean {
			return _initialized;
		}	
		
		public function get origin():String {
			return _origin;
		}
		
		public function set origin(value:String):void {
			_origin = value;
			if (value == null || value.length == 0) throw('Origin value must be defined');
			if(_ssl){
				_origin = "https://" + value;
			}
			else {
				_origin = "http://" + value;
			}
			if (subscribeConnection) {
				subscribeConnection.origin = _origin;
			}
			environment.origin = _origin;
		}
		
		public function get ssl():Boolean {
			return _ssl;
		}
	}
}
