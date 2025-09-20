package com.elgris.usersapi.api;

import com.elgris.usersapi.models.User;
import com.elgris.usersapi.repository.UserRepository;
import io.jsonwebtoken.Claims;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.LinkedList;
import java.util.List;

@RestController()
@RequestMapping("/users")
public class UsersController {

    @Autowired
    private UserRepository userRepository;


    @RequestMapping(value = "/", method = RequestMethod.GET)
    @Transactional(readOnly = true)
    public List<User> getUsers() {
        List<User> response = new LinkedList<>();
        userRepository.findAll().forEach(response::add);

        return response;
    }

    @RequestMapping(value = "/{username}",  method = RequestMethod.GET)
    @Transactional(readOnly = true)
    public User getUser(HttpServletRequest request, @PathVariable("username") String username) {

        Object requestAttribute = request.getAttribute("claims");
        if((requestAttribute == null) || !(requestAttribute instanceof Claims)){
            throw new RuntimeException("Did not receive required data from JWT token");
        }

        Claims claims = (Claims) requestAttribute;

        if (!username.equalsIgnoreCase((String)claims.get("username"))) {
            throw new AccessDeniedException("No access for requested entity");
        }

        User user = userRepository.findOneByUsername(username);
        if (user == null) {
            throw new RuntimeException("User not found");
        }
        
        return user;
    }

}
