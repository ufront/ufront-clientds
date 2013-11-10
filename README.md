ufront-clientds
===============

ClientDS is a Data Store that lets your client code access (and cache) objects from your server's database.  It uses ufront-orm, ufront-remoting, and ufront-easyauth to keep make things as seamless as possible.

Notes
-----

Basically these classes let you request a DB object from the client 
using remoting.  At the moment we support get(), getMany(), all() and
search() (search is similar to dynamicSearch on the server).  Save and Delete
also work, and are linked to the `obj.delete()` and `obj.save` methods on 
the client.

It then returns a Promise (from the brilliant promhx library), so you can
safely queue up your code to execute when it is available.  It caches all 
requests, so if your code asks for the same object 5 times, it will only
make one HTTP request.  And if it's previously been cached, it will be available
immediately.

### Advantages of this approach

 * Don't need a separate API for simple read operations

 * Each request is cached, so if you request something 12 times it will only make one HTTP request.

 * You get to do this: 
          
       Promise.when(userLoaded, profileLoaded, commentsLoaded).then(function (user, profile, comments) { /* Do something */});

   And it will be smart about loading only what is required.

 * If you call request User[34], like above, but it has previously been
   loaded already, it will retrieve it from the cache and resolve the 
   promise straight away, so there is no delay for your client code and
   no extra load on your server. 
 
 * It's a stepping stone on the road towards having a persistant offline data-store that syncs with the DB online :)

### Implementation

You'll need to use ufcommon remoting, and add `clientds.ClientDsApi` to your API context.

    class Api implements UFApiContext
    {
        // Vendor
        public var clientDsAPI:ClientDsApi;
    }

Then on the Client, you'll need to give the ClientDS class access to your API.  So if you've set 
your ApiClient up like this:

    var remoting = new app.ApiClient("/remoting/", processRemotingError);

Then you'll pass the API onto ClientDS like this:

    clientds.ClientDs.api = remoting.clientDsAPI;

Then, to make this super easy, we attach a ClientDs object to each of your models, in much the same 
way as we attach a manager on the server.  Any model that extends ufront.db.Object will automatically
get the clientDS and manager fields, so if you have the following:

    class User extends ufront.db.Object
    {
        public var username:SString;
        public var password:SString;
    }

It will become:

    class User extends ufront.db.Object
    {
        public var username:SString;
        public var password:SString;

        #if server 
            public static var manager:sys.db.Manager<User> = new sys.db.Manager(User);
        #else 
            public static var clientDS:ClientDs<User> = new ClientDs(User);
        #end 
    }

This means, on your client, you can now do:

    var user34Ready = User.clientDS.get(34);
    user34Ready.then(function (user) {
        trace ('user 34 is ${user.username}');
        trace ('and their completely unencrypted password is ${user.password}, in case you were wondering.');
    });

And even cooler:

    var user34Ready = User.clientDS.get(34);
    user34Ready.then(function (user) {
        user.username = "superfruitybubbleprincess2013";
        var user34Saved = user.save();
        user34Saved.when(function (user)
        {
            trace ('User 34 changed their username to ${user.username} at ${user.modified}');
        });
    });
