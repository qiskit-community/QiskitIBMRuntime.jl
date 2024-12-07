# Get unique session ids from cached job info
session_ids = unique(Iterators.map(j -> j.session_id, Iterators.filter(j -> !isnothing(j.session_id), cached_jobs())))
