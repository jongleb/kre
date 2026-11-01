[@@@controller "books"]

[%%resource
{
  service = (module Books : Books.S);
  entity = Book;
  actions = [ Index Book_filter; Show; Create Book_draft; Remove ];
}]
