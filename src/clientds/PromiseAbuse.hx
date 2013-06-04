package clientds;

import clientds.Promise;

/**
* What does this do:
* 
* Lets you separate setting the value and firing the existing handlers
* 
* 1. Any existing then() calls before it is set will not fire.
* 2. If it is in a set() but not fired state, any calls to then() will still fire.
* 3. When we call fire(), it will fire the unknown calls
* 
* Why a promise abuse class?
* 
* Post.clientDs.get(1).then(function (p) { trace(p.author.name); });
* 
* // ClientDs processes request for Post:1
* // ClientDs returns result set, including the relation "author" object
* // As the processing is done
* 	// Post:1 resolves first
* 		// Callback fires
* 		// Attempts to get p.author.name
* 		// Which is, p.get_author().name
* 			// get_author() realises author hasn't been set yet, so does
* 			// Author.clientDs.get(1).then(function (v) this._author == v);
* 			// expecting it to be synchronous.  But it's not there yet.
* 	// Author:1 resolves second, too late
* 
* With the promise abuse in place
* 
* // ClientDs processes request for Post:1
* // ClientDs returns result set, including the relation "author" object
* // As the processing is done
* 	// Post:1 set first
* 		// No callback fired yet, we just use PromiseAbuse.setWithoutFiring();
* 	// Author:1 set second
* 	// Post:1 Fires
* 		// Callback fires
* 		// Attempts to get p.author.name
* 		// Which is, p.get_author().name
* 			// get_author() realises author hasn't been set yet, so does
* 			// Author.clientDs.get(1).then(function (v) this._author == v);
* 			// Now, even though the Author:1 promise hasn't fired, it has been set, so this is synchronous.  And it works happily.
* 
* 	// Author:1 Fires
* 
* Warning: using this is probably a bad idea.  I'm going to do it anyway.  Be warned.
*/

@:access(promhx.Promise)
class PromiseAbuse 
{
	public static function setWithoutFiring<T>(p:Promise<T>, val:T)
	{
		if (p._set) throw("Promise has already been resolved");
		p._set = true;
		p._val = val;
	}

	public static function fireWithoutSetting<T>(p:Promise<T>)
	{
		for (f in p._update){
			try f(p._val)
			catch (e:Dynamic) p.handleError(e);
		}
		p._update = new Array<T->Dynamic>();
	}
}