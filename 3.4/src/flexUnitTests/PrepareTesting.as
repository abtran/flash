package flexUnitTests
{
	import com.pubnub.Pn;

	public class PrepareTesting
	{
		public static function PnConfig(pn:Pn, sslFlag:Boolean = false, entryFlag:Boolean = false):void
		{
			pn = Pn.instance;
			var config:Object = {
				origin:		'pubsub.pubnub.com',
				publish_key:'demo',
				sub_key:	'demo',
				secret_key:	'',
				cipher_key:	'',
				ssl:		sslFlag};
			
			Pn.init(config);
		}
		
		public static function CreateUnqueChannel():String
		{
			return "single"+ (Math.random()*1000).toString() + (Math.random()*1000).toString() + (new Date().time).toString()
		}
	}
}