require 'ostruct'
class ActiveRecordAdapter
  
  def use_adapter?(results)
    if(is_many?(results) || is_single?(results))
      return true
    end
    false
  end
  
  def run(results)
    result_object = self.walk(results)
    return result_object
  end
  
  #utility method for writing attributes on an active record
  def write_attributes(ar,ob)
    columns = ar.attributes.map{|k,v| k}
    columns.each_with_index do |column,i|
      val = ar.send(:"#{column}")
      eval("ob.#{column}=val")
    end
    #turn the outgoing object into a VO if neccessary
    map = VoUtil.get_vo_definition_from_active_record(ar.class.to_s)
    if map != nil
      ob._explicitType = map[:outgoing]
    end
    ob
  end
  
  #this must be used for any open structs in the serializer. This is the only way I've found to bypass Object#id deprecation warnings.
  def safe_open_struct
    o = OpenStruct.new
    class << o
      attr_accessor :id
    end
    o
  end
  
  #utility method for checking deathly empties
  def is_empty?(ar)
    empty = false
    if ar.is_a?(Array)
      if ar.empty?
        empty = true
      end
    end
    if ar.nil? then empty = true end
    return empty
  end

  #utility method to find associations that were actually included in the query (":include")
  def active_associations(ar,reflections)
    na = []
    aa = ar.instance_variables
    reflections.each do |reflect|
      a = reflect[1]
      if aa.include?("@" + a.name.to_s)
        na << a
      end
    end
    na
  end
  
  #is the result an array of active records
  def is_many?(results)
    if(results.class.to_s == 'Array' && results[0].class.superclass.to_s == 'ActiveRecord::Base')
      return true
    end
    false
  end
  
  #is this result a single active record?
  def is_single?(results)
    if(results.class.superclass.to_s == 'ActiveRecord::Base')
      return true
    end
    false
  end
  
  #recursive result traversing.
  def walk(ar)
    if is_many?(ar)
      payload = []
      associations = active_associations(ar[0], ar[0].class.reflections)
      if(is_empty?(associations))
        write_multiple_no_reflections(ar,payload)
      else
        write_multiple(ar, payload, associations)
      end
    elsif is_single?(ar)
      payload = safe_open_struct
      associations = active_associations(ar, ar.class.reflections)
      if(is_empty?(associations))
        write_attributes(ar,payload)
      else
        write_single(ar,payload,associations)
      end
    end    
    payload
  end
  
  def write_single(ar, payload, associations)
    write_attributes(ar, payload)
    associations.each do |association|
      #association is an ActiveRecord::Reflection::MacroReflection class
      model = association.name.to_s
      association_value = ar.send(:"#{model}")
      if is_empty?(association_value)
        next
      end
      next_payload = self.walk(association_value)
      eval("payload.#{model}=next_payload")
    end
    payload
  end
  
  #write array of active records with no reflections
  def write_multiple_no_reflections(ar,payload)
    ar.each_with_index do |record,i|
      #write attributes on this object
      attributes_holder = safe_open_struct
      payload[i] = write_attributes(ar[i],attributes_holder)
    end
    payload
  end
  
  def write_multiple(ar, payload, associations)
    ar.each_with_index do |record,i|
      #write attributes on this object
      attributes_holder = safe_open_struct
      payload[i] = write_attributes(ar[i],attributes_holder)
      associations.each do |association|
        #association is an ActiveRecord::Reflection::MacroReflection class
        model = association.name.to_s
        association_value = ar[i].send(:"#{model}")
        if is_empty?(association_value)
          next
        end
        next_payload = self.walk(association_value)
        eval("payload[i].#{model}=next_payload")
      end
    end
    payload
  end
end