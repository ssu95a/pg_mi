function createXml( dco, itemsList )
{
    var size = itemsList.size();

    for( var i = 0; i < size; i++ ) 
    {
        var map = itemsList.get(i); // Java Map
    
        var itemDco = dco.append("item");
        
        itemDco.a("itemUUID").set( map.get("external_uuid") );
        var content = itemDco.e("content");

        content.e("familyName").set( map.get("last_name"   ));
        content.e("firstName" ).set( map.get("first_name"  ));
        content.e("patronymic").set( map.get("middle_name" ));
        content.e("birthDate" ).set( map.get("birth_date"  ));
        content.e("seriesPassportRF").set(map.get("doc_ser"));
        content.e("numberPassportRF").set(map.get("doc_num"));
        content.e("regionCode").set( map.get("region_code" ));

    //print("Row " + i + ": id=" + id + ", name=" + name + ", active=" + active);
    
    }
}

createXml( dco, itemsList );