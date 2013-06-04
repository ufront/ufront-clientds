package clientds;

#if macro
import haxe.macro.Expr;
import tink.macro.tools.ExprTools;
import haxe.macro.Type;
import haxe.macro.Context;
using tink.macro.tools.TypeTools;
import promhx.Promise;
using Lambda;
#end

/**
* Actually the same in almost every way as promhx.Promise, we just use a different static funciton.
*
* In fact, this doesn't even require inheritance, I've only done this so that we can simplify and stick with one import.
*/
class Promise<T> extends promhx.Promise<T>
{
	/** An exact mirror of promhx.Promise.allSet() */
	public inline static function allSet(as:Iterable<promhx.Promise<Dynamic>>): Bool return promhx.Promise.allSet(as);

	/** An exact mirror of promhx.Promise.promise() */
	public inline static function promise<T>(_val:T, ?errorf:Dynamic->Dynamic) : promhx.Promise<T> return promhx.Promise.promise(_val, errorf);

	/**
	 * Almost a complete copy of promhx.Promise.when, and usage is the same.
	 *
	 * The only difference is that we account for our hackery where we set/resolve at different times.
	 * When used with Promise.when(), this can result in the callback firing as each of the promises fires,
	 * because they are all set.
	 * 
	 * The workaround is simple: 
	 * In the return expression, add this check before firing the callback and resolving the combined promise.
	 * 
	 *     if ( Promise.allSet([p]) == false )
	 *
	 * Other than that, we removed the type parameter (it appeared unused), and everything else is the same.
	 *
	 * @todo - DRYify this.  Figure out a way to call Promise.when(), and just modify the single line of the return expr.
	 **/
	macro public static function when<T>(args:Array<ExprOf<Promise<Dynamic>>>):Expr{
		// just using a simple pos for all expressions
		var pos = args[0].pos;
		// Dynamic Complex Type expression
		var d = TPType("Dynamic".asComplexType());
		// Generic Dynamic Complex Type expression
		var p = "promhx.Promise".asComplexType([d]);
		var ip = "Iterable".asComplexType([TPType(p)]);
		//The unknown type for the then function, also used for the promise return
		var ctmono = Context.typeof(macro null).toComplex(true);
		var eargs:Expr; // the array of promises
		var ecall:Expr; // the function call on the promises

		// multiple argument, with iterable first argument... treat as error for now
		if (args.length > 1 && ExprTools.is(args[0],ip)){
			Context.error("Only a single Iterable of Promises can be passed", args[1].pos);
		} else if (ExprTools.is(args[0],ip)){ // Iterable first argument, single argument
			var cptypes =[Context.typeof(args[0]).toComplex(true)];
			eargs = args[0];
			ecall = macro {
				var arr = [];
				for (a in $eargs) arr.push(a._val);
				f(arr);
			}
		} else { // multiple argument of non-iterables
			for (a in args){
				if (ExprTools.is(a,p)){
					//the types of all the arguments (should be all Promises)
					var types = args.map(Context.typeof);
					//the parameters of the Promise types
					var ptypes = types.map(function(x) switch(x){
						case TInst(_,params): return params[0];
						default : {
							Context.error("Somehow, an illegal promise value was passed",pos);
							return null;
						}
					});
					var cptypes = ptypes.map(function(x) return x.toComplex(true)).array();
					//the macro arguments expressed as an array expression.
					eargs = {expr:EArrayDecl(args),pos:pos};

					// An array of promise values
					var epargs = args.map(function(x) {
						return {expr:EField(x,"_val"),pos:pos}
					}).array();
					ecall = {expr:ECall(macro f, epargs), pos:pos}
				} else{
					Context.error("Arguments must all be Promise types, or a single Iterable of Promise types",a.pos);
				}
			}
		}

		// the returned function that actually does the runtime work.
		return macro {
			var parr:Array<Promise<Dynamic>> = $eargs;
			var p = new Promise<$ctmono>();
			{
				then : function(f){
					 //"then" function callback for each promise
					var cthen = function(v:Dynamic){
						if ( Promise.allSet(parr)){
							try{ 
								if ( Promise.allSet([p]) == false )
									untyped p.resolve($ecall); 
							}
							catch(e:Dynamic){
								untyped p.handleError(e);
							}
						}
					}
					if (Promise.allSet(parr)) cthen(null);
					else for (p in parr) p.then(cthen);
					return p;
				}
			}
		}
	}
}