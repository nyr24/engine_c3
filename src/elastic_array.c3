module std::collections::elastic_array <Type, MAX_SIZE>;

import util;

<*
	@require new_cap <= MAX_SIZE : "Would exceed maximum capacity"
*>
fn void ElasticArray.resize(&self, usz new_cap)
{
	self.size = new_cap;
}

fn void ElasticArray.resize_to_cap(&self)
{
	self.size = MAX_SIZE;
}

fn Type* ElasticArray.data(&self)
{
	return &self.entries;
}

fn void ElasticArray.fill(&self, Type val)
{
	foreach (&entry : self.array_view()) {
		*entry = val;
	}
}

fn void ElasticArray.remove_unordered(&self, usz ind)
{
	assert(ind < self.size);
	util::@swap_ptrs(&self[ind], &self[self.size - 1]);
	self.size--;
}
