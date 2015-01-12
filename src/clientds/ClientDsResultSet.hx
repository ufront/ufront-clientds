package clientds;

import haxe.ds.*;
import ufront.db.Object;
import sys.db.Types;
import thx.core.Dynamics;
using Lambda;

typedef ObjectList = IntMap<Object>;
typedef TypedObjectList<T:ufront.db.Object> = IntMap<T>;

class ClientDsResultSet
{
	public var length(default,null):Int;
	var m:StringMap<ObjectList>; // [ modelName => [ id => object ] ]
	var searchRequests:StringMap<Array<{}>>;
	var allRequests:Array<String>;

	public function new()
	{
		length = 0;
		m = new StringMap();
		searchRequests = new StringMap();
		allRequests = [];
	}

	// For writing

	public function addItems(?name:String, items:Iterable<Object>)
	{
		if ( name==null ) name = guessName( items );

		// get the IntMap for this model
		if (!m.exists(name)) m.set(name, new IntMap());
		var intMap = m.get(name);

		// Populate it
		for (i in items)
		{
			if (!intMap.exists(i.id))
				length++;
			intMap.set(i.id, i);
		}
		return intMap;
	}

	public function addAll(?name:String, items:Iterable<Object>)
	{
		if ( name==null ) name = guessName( items );
		if (!allRequests.has(name)) allRequests.push(name);
		return addItems(name, items);
	}

	public function addSearchResults(?name:String, criteria:{}, items:Iterable<Object>)
	{
		if ( name==null ) name = guessName( items );
		if (!searchRequests.exists(name)) searchRequests.set(name, []);
		searchRequests.get(name).push(criteria);

		return addItems(name, items);
	}

	function guessName( items:Iterable<Object> ) {
		var name = "";
		for ( i in items ) {
			name = Type.getClassName( Type.getClass(i) );
			break;
		}
		return name;
	}

	// For reading

	public function allItems():List<Object>
	{
		var all = new List();
		for (l in m)
		{
			for (o in l) all.push(o);
		}
		return all;
	}

	public function models():Array<Class<Object>>
	{
		return cast [ for (n in m.keys()) Type.resolveClass(n) ];
	}

	public function items<T:Object>(model:Class<T>):TypedObjectList<T>
	{
		var name = Type.getClassName(model);
		return (m.exists(name)) ? cast m.get(name) : new IntMap<T>();
	}

	public function item<T:Object>(model:Class<T>, id:SUId):Null<T>
	{
		var name = Type.getClassName(model);
		return (m.exists(name)) ? cast m.get(name).get(id) : null;
	}

	public function searches(model:Class<Dynamic>):Array<{}>
	{
		var name = Type.getClassName(model);
		var searches = searchRequests.get(name);
		return (searches != null) ? searches : [];
	}

	public function searchResults<T:Object>(model:Class<T>, criteria:{}):Null<IntMap<T>>
	{
		var name = Type.getClassName(model);

		// If this search was done
		if (hasSearchRequest(name, criteria))
		{
			// Filter the list by criteria and return them
			var total = Lambda.count(m.get(name));
			var result = Lambda.count(ClientDsUtil.filterByCriteria(m.get(name),criteria));
			var criteriaStr = haxe.Json.stringify( criteria );
			return cast ClientDsUtil.filterByCriteria(m.get(name), criteria);
		}
		return null;
	}

	public function toString():String
	{
		var sb = new StringBuf();
		sb.add('Found $length items total \n');
		for (model in models())
		{
			var name = Type.getClassName(model);
			var count = items(model).count();
			sb.add('  $name : $count items\n');
		}
		return sb.toString();
	}

	// Functions so we can check if a new request has to be made

	public function hasGetRequest(name:String, id:SUId)
		return (allRequests.indexOf(name) != -1) || (m.exists(name) && m.get(name).exists(id));

	public function hasAllRequest(name:String)
		return allRequests.indexOf(name) != -1;

	public function hasGetManyRequest(name:String, ids:Array<SUId>)
	{
		if (allRequests.indexOf(name) != -1) return true;

		var intMap = m.get(name);
		if (intMap == null) return false;

		for (id in ids)
		{
			if (!intMap.exists(id)) return false;
		}
		return true;
	}

	public function hasSearchRequest(name:String, criteria:{})
	{
		var matchFound = false;
		if (allRequests.indexOf(name) != -1)
		{
			matchFound = true;
		}
		else if (searchRequests.exists(name))
		{
			for (c in searchRequests.get(name))
			{
				if (Dynamics.equals(criteria,c))
				{
					matchFound = true;
					break;
				}
			}
		}
		return matchFound;
	}
}
