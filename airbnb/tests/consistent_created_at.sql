select r.* from {{ref('fct_reviews')}} r
join {{ref('dim_listings_cleansed')}} d on d.listing_id = r.listing_id
where d.created_at > r.review_date 