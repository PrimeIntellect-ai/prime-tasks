import sys
import pandas as pd

def main():
    if len(sys.argv) < 2:
        return
    target_tag = sys.argv[1]

    users = pd.read_csv('/app/data/users.csv')
    posts = pd.read_csv('/app/data/posts.csv')
    tags = pd.read_csv('/app/data/tags.csv')
    post_tags = pd.read_csv('/app/data/post_tags.csv')

    tag_match = tags[tags['tag_name'] == target_tag]
    if tag_match.empty:
        print("")
        return
    tag_id = tag_match.iloc[0]['tag_id']

    pt_match = post_tags[post_tags['tag_id'] == tag_id]
    post_ids = pt_match['post_id'].unique()

    authors = posts[posts['post_id'].isin(post_ids)]['author_id'].unique()

    matched_users = users[(users['user_id'].isin(authors)) & (users['country'] == 'Canada')]

    user_ids = sorted(matched_users['user_id'].tolist())
    print(" ".join(map(str, user_ids)))

if __name__ == '__main__':
    main()
