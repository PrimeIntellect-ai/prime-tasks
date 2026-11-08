Updating Scores to a Specific Rubric
**What resource needs additional coverage?**
Rubrics

**What endpoints need to be covered?**
Requested here is a method that would allow one to upload scores on a specific rubric for a specific assignment. Ideally this would include the ability to add scores for multiple different criteria within the specified rubric. As @bennettscience noted in a discussion [here](https://github.com/ucfopen/canvasapi/discussions/537#discussioncomment-3132545), one can go directly through the Canvas API, but it would be nice to have a function to handle this from within directly through the canvasapi library itself.

### Additional contract requirements

Expose the score-submission operation as `RubricAssociation.create_rubric_assessment(**kwargs)`. It must send a POST to `courses/{course_id}/rubric_associations/{rubric_association_id}/rubric_assessments` for the association's course and rubric association. The request must identify the assignment submission with `artifact_type` and `artifact_id`, and forward scores for multiple rubric criteria in one submission.
