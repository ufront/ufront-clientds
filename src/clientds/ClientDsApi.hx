package clientds;

import sys.db.Types;
using tink.CoreApi;
using Lambda;
import ufront.api.UFApi;
import ufront.db.Object;
import ufront.db.ManyToMany;
import ufront.web.HttpError;
import haxe.ds.*;
import clientds.ClientDsResultSet;
import clientds.ClientDsRequest;
import haxe.rtti.Meta;
#if server 
	import sys.db.Manager;
	import ufront.sys.SysUtil;
#end 

class ClientDsApi extends UFApi
{
	@inject("contentDirectory") public var contentDir:String;

	public function get(req:ClientDsRequest, fetchRel:Bool):Outcome<ClientDsResultSet, String>
	{
		try 
		{
			var rs = doGet(req, false, fetchRel);
			return Success(rs);
		}
		catch (e:String)
		{
			var cs = haxe.CallStack.toString( haxe.CallStack.exceptionStack() );
			return Failure('Failed to get core data: $e\n$cs');
		}
	}

	public function getCached(req:ClientDsRequest, fetchRel:Bool, cacheName:String):String
	{
		var dir = contentDir + "cache/";
		var cacheFile = dir + cacheName;
		var rsSerialised:String;
		
		if (sys.FileSystem.exists(cacheFile))
		{
			rsSerialised = sys.io.File.getContent(cacheFile);
		}
		else
		{
			rsSerialised = reloadCache(req,fetchRel,cacheName).sure();
		}

		return rsSerialised;
	}

	public function reloadCache(req:ClientDsRequest, fetchRel:Bool, cacheName:String):Outcome<String,Error>
	{
		var dir = contentDir + "cache/";
		var cacheFile = dir + cacheName;
		var rsSerialised:String = null;
		
		try
		{
			trace('Reloading cache for request: $req');
			trace('Fetch relationships: $fetchRel');
			trace('Cache name: $cacheName');
			var result = get(req, fetchRel);
			trace('Received this response: $result');
			// Throw an error if the get() request failed, so we can retry.
			result.sure();
			rsSerialised = haxe.Serializer.run(result);
			haxe.Unserializer.run( rsSerialised );
			SysUtil.mkdir( dir );
			sys.io.File.saveContent(cacheFile, rsSerialised);
		}
		catch (e:Dynamic) 
		{
			if ( rsSerialised==null )
			{
				return Failure( HttpError.internalServerError('Failed to fetch ClientDS request: $e', e) );
			}
			else
			{
				// There was an error, but it's non fatal. Let's log it and still return a Success.
				trace( 'Failed to save ClientDS cache $cacheFile: $e' );
			}
		}
		return Success( rsSerialised );
	}

	/** 
	* Save some objects to the database by calling save() on each one
	* 
	* @param map of objects to save: "aModelName" => [aObject1, aObject2], "bModelName" => [bObject1, bObject2]
	* @return This returns a StringMap with the same keys as the original, and an array for each value, with the
	*   same number of items as the original arrays.  Inside the array, at the same location, is an outcome.  If
	*   the save was successful, the outcome contains the ID of the object that was saved.  If the save failed,
	*   the outcome contains the error message for that save.
	*   
	* Currently this does no optimisations for bulk SQL inserts... not sure if I want that, as it would skip our save()
	* method which does validation/permission checks.
	*/
	public function save(map:Map<String, Array<ufront.db.Object>>):StringMap<Array<Outcome<SUId, String>>>
	{
		if (map == null) return new StringMap();

		var retMap = new StringMap();

		for (modelName in map.keys())
		{
				var objects = map.get(modelName);
				if (objects != null)
				{
						var a:Array<Outcome<SUId, String>> = [];
						for (o in map.get(modelName))
						{
							try 
							{
									o.save();
									a.push(Success(o.id));
							}
							catch (e:String)
							{
									a.push(Failure(e));
							}
						}
						retMap.set(modelName, a);
				}
		}

		return retMap;
	}

	/** 
	* Delete some objects from the database by calling delete() on each one
	* 
	* @param map of objects to delete: "aModelName" => [1, 2], "bModelName" => [1, 2]
	* @return This returns a StringMap with the same keys as the original, and an array for each value, with the
	*   same number of items as the original arrays.  Inside the array, at the same location, is an outcome.  If
	*   the save was successful, the outcome contains the ID of the object that was saved.  If the save failed,
	*   the outcome contains the error message for that save.
	*   
	* Currently this does no optimisations for bulk SQL removals... not sure if I want that, as it would skip 
	* any onDelete() callbacks (not that they're even implemented yet...)
	*/
	@:access(sys.db.Manager)
	public function delete(map:Map<String, Array<SUId>>):StringMap<Array<Outcome<SUId, String>>>
	{
		if (map == null) return new StringMap();

		var retMap = new StringMap();

		for (modelName in map.keys())
		{
				var objects = map.get(modelName);
				var model = getModel(modelName);
				var manager = getManager(model);
				if (objects != null)
				{
						var a:Array<Outcome<SUId, String>> = [];
						for (id in map.get(modelName))
						{
								try 
								{
										var tableName = manager.table_name;
										var quotedID = manager.quoteField('$id');
										manager.unsafeDelete('DELETE FROM $tableName WHERE `id` = $quotedID');
										a.push(Success(id));
								}
								catch (e:String)
								{
										a.push(Failure(e));
								}
						}
						retMap.set(modelName, a);
				}
		}

		return retMap;
	}

	@:access(sys.db.Manager)
	function doGet(req:ClientDsRequest, ?resultSet:ClientDsResultSet, ?originalRequest:Bool=true, ?fetchRel:Bool):ClientDsResultSet
	{
		if (resultSet == null) resultSet = new ClientDsResultSet();

		var map = req.requests;

		for (name in map.keys())
		{
			var model = getModel(name);
			var manager = getManager(model);
			var requests = map.get(name);

			// Do "all" requests first, so any dependant searches are cached

			var allList:List<Object> = null;
			if (requests.all)
			{
				allList = manager.all();
				var intMap = resultSet.addAll(name, allList);
			}

			// Do searches next, as these will likely have the most matches.  Again, cache as much as possible.

			for (s in requests.search)
			{
				var criteria = s;
				if (!requests.all)
				{
					// Else, make a new request
					var list = manager.dynamicSearch(criteria);
					resultSet.addSearchResults(name, criteria, list);
				}
				// else 
					// If there was an all request, the results will already be in our resultSet.
					// and ClientDS on the client will be smart enough to just filter.  So no need
					// to run resultSet.addSearchResults(name, criteria, list)
			}
			
			// Create a request for the remainder (only if length of list > 0)
			var tableName = manager.table_name;
			var ids = requests.get.filter(function (id) return (!resultSet.hasGetRequest(name, id)));
			
			if (ids.length > 0)
			{
				var list = manager.unsafeObjects("SELECT * FROM `" + tableName + "` WHERE " + Manager.quoteList("id", ids), false);
				resultSet.addItems(name, list);
			}
		}

		// Do all relationship searching after first pass
		if (fetchRel)
		{
			var relationsToGet = findRelations(resultSet);
			
			// If there are relationships to fetch... get them now
			if (relationsToGet.empty == false)
			{
				// Trace the extra relations we're fetching
				#if debug
					trace ('ClientDS fetching extra relations (RS has ${resultSet.length}): \n${relationsToGet.toString()}');
				#end
				doGet(relationsToGet, resultSet, false, fetchRel);
			}
		}

		return resultSet;
	}

	@:access(ufront.db.ManyToMany)
	function findRelations(rs:ClientDsResultSet):ClientDsRequest
	{
		var req = new ClientDsRequest();
		for (model in rs.models())
		{
			var l:IntMap<Object> = rs.items(model);

			var relationshipStrings:Array<String> = cast Meta.getType(model).ufRelationships;

			if (relationshipStrings!=null && relationshipStrings.length > 0)
			{
				var relationships:Array<{property:String,relType:String,model:Class<Object>,foreignKey:Null<String>}> = [];
				for (s in relationshipStrings)
				{
					var parts = s.split(",");
					var foreignModelName = parts[2];
					var r = {
						property: parts[0],
						relType: parts[1],
						model: cast Type.resolveClass(foreignModelName),
						foreignKey: (parts.length > 3) ? parts[3] : null
					};
					relationships.push(r);

					// We'll process all of the ManyToMany joins now, rather than in the loop below.  Should be more efficient.
					if (r.relType == "ManyToMany")
					{
						// If this model doesn't have an "all" request, fetch individual IDs to find joins for.  
						// Otherwise we'll get the whole join table
						var joins:IntMap<List<Int>> = null;
						if (rs.hasAllRequest(Type.getClassName(model)) == false)
						{
							var ids = l.map(function (obj) return obj.id);
							joins = ManyToMany.relatedIDsforObjects(model,r.model,ids);
						}
						else 
						{
							joins = ManyToMany.relatedIDsforObjects(model,r.model);
						}

						for (aID in joins.keys())
						{
							// If aID is in our original list
							if (l.exists(aID))
							{
								// Add the items to the result set
								var list = joins.get(aID);
								for (bID in list) {
									addGetToRequestIfNotInResultSet(rs, req, r.model, bID);
								}
								
								// TODO:
								// If we have a corrupt join table, where some of the join records do not have matching objects,
								// we can get stuck in an infinite loop here.  How it happens: we request an object, and fetchRel==true,
								// so we do a getMany( relatedIDs ), but if one of those IDs doesn't exist, we'll get to the end of get(),
								// fetchRel is still true, but it realizes we're still missing some objects (the ones that don't exist),
								// so it gets stuck in a loop.
								// The solution will be to change addGetToRequestIfNotInResultSet(), to also check that it's not something
								// we searched for already but didn't exist.

								// Let's take the time to initiate the private ManyToMany variable
								var o = l.get(aID);
								var m2m = new ManyToMany(o, r.model, false);
								m2m.bListIDs = list;
								Reflect.setField(o, r.property, m2m);
							}
						}
					}
				}

				// This whole thing could probably be optimised a lot more.  I don't know how many calls to ManyToMany.isABeforeB() etc are being made
				for (obj in l)
				{
					for (r in relationships)
					{
						switch (r.relType)
						{
							case "BelongsTo":
								addGetToRequestIfNotInResultSet(rs, req, r.model, Reflect.field(obj, r.property));
							case "HasMany" | "HasOne":
								var criteria = {};
								Reflect.setField(criteria, r.foreignKey, obj.id);
								addSearchToRequestIfNotInResultSet(rs, req, r.model, criteria);
							case "ManyToMany":
								// We added these relationships above, outside of this loop
							default:
						}
					}
				}
			}
		}
		return req;
	}

	function addGetToRequestIfNotInResultSet(rs:ClientDsResultSet, req:ClientDsRequest, model:Class<Object>, id:Int, ?fetchRelations:Bool):ClientDsRequest
	{
		if (!rs.hasGetRequest(Type.getClassName(model), id)) {
			req.get(model, id);
		}

		return req;
	}

	function addSearchToRequestIfNotInResultSet(rs:ClientDsResultSet, req:ClientDsRequest, model:Class<Object>, criteria:{}, ?fetchRelations:Bool):ClientDsRequest
	{
		if (!rs.hasSearchRequest(Type.getClassName(model), criteria))
			req.search(model, criteria);

		return req;
	}

	#if server 
		function getModel(modelName:String):Class<Object>
		{
			var modelCl:Class<Object> = cast Type.resolveClass(modelName);

			// If class wasn't found, return failure
			if (modelCl == null)
				throw 'The model $modelName was not found';

			// Hopefully by this point everything is safe to cast
			return modelCl;
		}

		function getManager(modelCl:Class<Object>):Manager<Object>
		{
			// If there is no "manager", return failure
			if (Reflect.hasField(modelCl, "manager") == false)
				throw 'The model ${Type.getClassName(modelCl)} had no field "manager"';

			// Try to create an instance of the manager
			var manager:Manager<Object> = Reflect.field(modelCl, "manager");

			// Check it's a valid manager
			if (!Std.is(manager, sys.db.Manager)) throw 'The manager for ${Type.getClassName(modelCl)} was not valid.';

			// Hopefully by this point everything is safe to cast
			return manager;
		}
	#end
}