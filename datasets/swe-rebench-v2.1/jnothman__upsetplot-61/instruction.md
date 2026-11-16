Feature Request: more intuitive data conversion
Currently there are three ways to use your library:

1.  generate data via the `generate_data` method
2. construct data via the `from_membership` method
3. be comfortable enough with Pandas to coerce your data to fit the expected shape (for which there is no documentation how to do)

The issue with point 2 is that it is both verbose and not how users actually keep their data and since there isn't a guide for point 3 yet many users may just ignore your library, despite you main selling point being that the alternative library lacks documentation for the input format (your documentation I would say hardly counts as a counter point.


So how might users actually store their data?

Well they probably have named sets, with elements rather than parts of venn-diagrams and the number of elements therein e.g.

```JSON
{
    "Set1": ["el1", "el2"],
    "Set2": ["el2", "el4"],
    ,...
}
```


So lets add some helper functions to would take something like above and make it compatible with your data format (this is from my personal collection of helper functions)


```python
from itertools import combinations

def subsets(setnames:list) -> list:
    ''' Gives the 2^n subsets for every set in setnames

    Args:
        setnames (list): a list of elements, where each element corresponds to
            the name of a set. e.g. ['A', 'B', ..., 'Z']
    Returns:
        subsets (list): a list of tuples, where each tuple contains the set
            names corresponding to the sets in that subset

            e.g. [(), (A, ), (B, ), ..., (A, B, ), ... (A, B, ..., Z)]
    '''
    number_of_sets = len(setnames)
    return [
        combination
        for combination_index in range(number_of_sets)
        for combination in list(combinations(setnames, combination_index))
    ] + [tuple(setnames)]

def partitions_by_length(partitions:list):
    '''Groups partitions by number of sets in each partition

    Args:
        partitions (list): a list of lists, where each sublist represents a
            partititon and each item therein corresponds to the name of a set.

            e.g. the output of subsets

    Returns:

        partitons_by_length (dict): {num: partitons} pairs where num is an int
            specifiy the number of sets in each partition, and partitions is
            a list containing all partitions with num sets.

    '''
    grouped = {}
    for partition in partitions:
        cardinality = len(partition)
        if cardinality not in grouped:
            grouped[cardinality] = []
        grouped[cardinality].append(partition)
    return grouped

def upset_elements(sets:dict, domain:set=set({})) -> dict:
    '''Gives the elements unique to each ~region~ of the venn diagram

    Args:
        sets (dict): the pair of {setname (str): elements (list)} for which to
            compute on

        domain (set): all the elements, including those which may not be seen in
            the passed sets. By default, an empty set.

    Returns:
        elements_unique_to_comparisons (dict): a dict containing the pair of
            {comparison (tuple): elements (list)}, where comparison is a tuple
            of setnames (keys from sets), e.g. ('A', 'B',) indicating the
            comparison made.

    '''
    setnames = list(sets.keys())
    # returns partitions of setnames in increasing number of sets, e.g.
    # [(), (A, ), (B, ), ..., (A, B, ), ... (A, B, ..., Z)]
    comparisons = subsets(setnames)
    comparisons.reverse()

    # group each comparison by how many sets in each comparisons e.g.
    # work our way from the inner most of the venn diagram to the outer most
    grouped_comparisons = partitions_by_length(comparisons)

    # results
    elements_unique_to_comparisons = {}

    # elements we have already seen
    seen = set({})

[HIDDEN]
```


In this particular instance we are assuming all elements are strings. So let us add one more helper method:

```python


def to_sets(dictionary:dict, to_lower_case:bool=True):
    '''
    Arguments:
        dictionary (dict): key, value pairs where keys are setnames and values are lists of elements in the sets.
    Returns:
        result (dict): key, value pairs where the values are now all sets.
    '''
    sets = {}
    for key, val in dictionary.items():
        sets[key] = set([v.lower() for v in val])
    return sets
```


Great now let's see how this works in practice

```python
# load sets
with open('sets.json', 'r') as f:
    data = json.load(f)

# get elements unique to each part of the venn diagram
upset_data = upset_elements(to_sets(data)) #**

# list of tuples corresponding to what sets correspond to the venn diagram part
subsets = list(upset_data.keys())

# filter out empty subsets
min_subsets_e = list(filter(lambda t: len(upset_data[t])>0, subsets))

# convert to your format
plot_data = from_memberships(
    [list(e) for e in min_subsets],
    data=[len(upset_data[ss]) for ss in min_subsets]
)
```

** note the `upset_data` is a more useful format than the input format as it lets users also keep track of which element is in what part of the venn diagram, rather than just know the cardinality of that subset.



Anyway, it is my __personal__ opinion that your library would be better off including such converter functions to make it easier to use, especially to those who are not the most familiar with Pandas.

### Additional contract requirements

Expose the conversion as `upsetplot.from_contents(contents)`. It must return a dataframe in the format accepted by UpSetPlot, with one membership level in its index for each named set and an `id` column that preserves each input element's identity, with each element represented once. Each element's membership levels must indicate exactly which named sets contain it.
